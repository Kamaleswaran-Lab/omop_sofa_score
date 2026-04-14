
-- 52_cdc_ase_qad.sql
-- Qualifying Antimicrobial Days (QAD) per CDC
-- FIXED v2: no window functions in WHERE

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

DROP TABLE IF EXISTS :results_schema.cdc_ase_qad;
CREATE TABLE :results_schema.cdc_ase_qad AS
WITH ordered AS (
  SELECT *,
    LAG(drug_day) OVER (PARTITION BY person_id, visit_occurrence_id, drug_concept_id ORDER BY drug_day) AS prev_day_same
  FROM :results_schema.cdc_ase_drug_days
),
new_starts AS (
  SELECT *,
    CASE 
      WHEN prev_day_same IS NULL OR (drug_day - prev_day_same) > 2 THEN 1
      ELSE 0
    END AS is_new_antimicrobial
  FROM ordered
)
SELECT * FROM new_starts;

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
    q.is_new_antimicrobial
  FROM bc
  JOIN :results_schema.cdc_ase_qad q 
    ON q.person_id = bc.person_id AND q.visit_occurrence_id = bc.visit_occurrence_id
  WHERE q.drug_day BETWEEN bc.culture_date - 2 AND bc.culture_date + 2
),
first_iv AS (
  SELECT person_id, visit_occurrence_id, culture_date,
    MIN(drug_day) AS first_iv_new_day
  FROM qad_window
  WHERE is_new_antimicrobial = 1 AND route_category = 'IV'
  GROUP BY 1,2,3
),
eligible_qad AS (
  SELECT 
    qw.person_id, qw.visit_occurrence_id, qw.culture_date, qw.drug_day,
    f.first_iv_new_day
  FROM qad_window qw
  JOIN first_iv f USING (person_id, visit_occurrence_id, culture_date)
  JOIN :results_schema.cdc_ase_qad q2 
    ON q2.person_id = qw.person_id 
    AND q2.visit_occurrence_id = qw.visit_occurrence_id
    AND q2.drug_day = qw.drug_day
  WHERE qw.drug_day >= f.first_iv_new_day
),
-- Find consecutive sequences
with_groups AS (
  SELECT *,
    drug_day - (ROW_NUMBER() OVER (PARTITION BY person_id, visit_occurrence_id, culture_date ORDER BY drug_day) * INTERVAL '1 day') AS grp
  FROM eligible_qad
),
group_counts AS (
  SELECT person_id, visit_occurrence_id, culture_date, grp,
    COUNT(*) AS consecutive_days,
    MIN(drug_day) AS seq_start,
    MAX(drug_day) AS seq_end,
    MAX(first_iv_new_day) AS first_iv
  FROM with_groups
  GROUP BY 1,2,3,4
  HAVING COUNT(*) >= 4
)
SELECT 
  person_id, visit_occurrence_id, culture_date,
  seq_start AS first_qad_date,
  consecutive_days AS qad_count,
  seq_end AS last_qad_date,
  first_iv AS first_iv_new_day
FROM group_counts;
