
-- 52_cdc_ase_qad.sql
-- Qualifying Antimicrobial Days (QAD) per CDC
-- Requires drug_exposure with antimicrobial concepts
-- FIXED: date arithmetic for PostgreSQL

DROP TABLE IF EXISTS :results_schema.cdc_ase_drug_days;
CREATE TABLE :results_schema.cdc_ase_drug_days AS
SELECT DISTINCT
  de.person_id,
  de.visit_occurrence_id,
  DATE(de.drug_exposure_start_datetime) AS drug_day,
  de.drug_concept_id,
  LOWER(c.concept_name) AS drug_name,
  CASE WHEN de.route_concept_id IN (4132161,4139562) THEN 'IV' ELSE 'PO' END AS route_category
FROM :cdm_schema.drug_exposure de
JOIN :results_schema.cdc_ase_antimicrobial_concepts ac ON ac.concept_id = de.drug_concept_id
JOIN :vocab_schema.concept c ON c.concept_id = de.drug_concept_id
WHERE de.visit_occurrence_id IS NOT NULL;

-- Collapse to QAD logic
DROP TABLE IF EXISTS :results_schema.cdc_ase_qad;
CREATE TABLE :results_schema.cdc_ase_qad AS
WITH ordered AS (
  SELECT *,
    LAG(drug_day) OVER (PARTITION BY person_id, visit_occurrence_id, drug_concept_id ORDER BY drug_day) AS prev_day_same,
    LAG(drug_day) OVER (PARTITION BY person_id, visit_occurrence_id ORDER BY drug_day, drug_concept_id) AS prev_any_day
  FROM :results_schema.cdc_ase_drug_days
),
new_starts AS (
  SELECT *,
    CASE 
      WHEN prev_day_same IS NULL OR (drug_day - prev_day_same) > 2 THEN 1
      ELSE 0
    END AS is_new_antimicrobial
  FROM ordered
),
qad_flagged AS (
  SELECT *,
    SUM(is_new_antimicrobial) OVER (PARTITION BY person_id, visit_occurrence_id ORDER BY drug_day ROWS UNBOUNDED PRECEDING) AS antimicrobial_episode
  FROM new_starts
)
SELECT 
  person_id,
  visit_occurrence_id,
  drug_day,
  drug_concept_id,
  drug_name,
  route_category,
  is_new_antimicrobial,
  antimicrobial_episode
FROM qad_flagged;

-- Build 4-day sequences
DROP TABLE IF EXISTS :results_schema.cdc_ase_presumed_infection;
CREATE TABLE :results_schema.cdc_ase_presumed_infection AS
WITH bc AS (
  SELECT * FROM :results_schema.cdc_ase_blood_cultures
),
qad_window AS (
  SELECT 
    bc.person_id,
    bc.visit_occurrence_id,
    bc.culture_date,
    q.drug_day,
    q.route_category,
    q.is_new_antimicrobial,
    CASE WHEN q.drug_day BETWEEN bc.culture_date - 2 AND bc.culture_date + 2 THEN 1 ELSE 0 END AS in_window
  FROM bc
  JOIN :results_schema.cdc_ase_qad q 
    ON q.person_id = bc.person_id AND q.visit_occurrence_id = bc.visit_occurrence_id
),
first_new_in_window AS (
  SELECT person_id, visit_occurrence_id, culture_date,
    MIN(drug_day) FILTER (WHERE in_window=1 AND is_new_antimicrobial=1 AND route_category='IV') AS first_iv_new_day
  FROM qad_window
  GROUP BY 1,2,3
),
consecutive_qad AS (
  SELECT 
    w.person_id, w.visit_occurrence_id, w.culture_date,
    w.drug_day,
    ROW_NUMBER() OVER (PARTITION BY w.person_id, w.visit_occurrence_id, w.culture_date ORDER BY w.drug_day) AS rn,
    -- FIXED: use date - integer arithmetic properly
    w.drug_day - (ROW_NUMBER() OVER (PARTITION BY w.person_id, w.visit_occurrence_id, w.culture_date ORDER BY w.drug_day) * INTERVAL '1 day') AS grp
  FROM qad_window w
  JOIN first_new_in_window f USING (person_id, visit_occurrence_id, culture_date)
  WHERE f.first_iv_new_day IS NOT NULL
    AND w.drug_day >= f.first_iv_new_day
    AND w.drug_day BETWEEN f.first_iv_new_day AND f.first_iv_new_day + INTERVAL '10 days'
)
SELECT 
  person_id, visit_occurrence_id, culture_date,
  MIN(drug_day) AS first_qad_date,
  COUNT(*) AS qad_count,
  MAX(drug_day) AS last_qad_date,
  MAX(first_iv_new_day) AS first_iv_new_day
FROM (
  SELECT c.*, f.first_iv_new_day,
    COUNT(*) OVER (PARTITION BY person_id, visit_occurrence_id, culture_date, grp) AS consecutive_days
  FROM consecutive_qad c
  JOIN first_new_in_window f USING (person_id, visit_occurrence_id, culture_date)
) t
WHERE consecutive_days >= 4
  AND MIN(drug_day) OVER (PARTITION BY person_id, visit_occurrence_id, culture_date) 
      BETWEEN culture_date - INTERVAL '2 days' AND culture_date + INTERVAL '2 days'
GROUP BY person_id, visit_occurrence_id, culture_date;
