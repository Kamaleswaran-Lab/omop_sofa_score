-- 52_cdc_ase_qad.sql
-- Qualifying Antimicrobial Days (QAD) per CDC Adult Sepsis Event definition
-- Includes death/discharge exception for <4 days
-- Optimized for PostgreSQL

DROP TABLE IF EXISTS :results_schema.cdc_ase_drug_days;
CREATE TABLE :results_schema.cdc_ase_drug_days AS
SELECT DISTINCT
  de.person_id, de.visit_occurrence_id,
  DATE(de.drug_exposure_start_datetime) AS drug_day,
  de.drug_concept_id, LOWER(c.concept_name) AS drug_name,
  CASE WHEN de.route_concept_id IN (4132161,4139562) THEN 'IV'
       WHEN de.route_concept_id IS NULL THEN 'IV' ELSE 'PO' END AS route_category
FROM :cdm_schema.drug_exposure de
JOIN :results_schema.cdc_ase_antimicrobial_concepts ac ON ac.concept_id = de.drug_concept_id
JOIN :vocab_schema.concept c ON c.concept_id = de.drug_concept_id
WHERE de.visit_occurrence_id IS NOT NULL;

DROP TABLE IF EXISTS :results_schema.cdc_ase_qad;
CREATE TABLE :results_schema.cdc_ase_qad AS
WITH ordered AS (
  SELECT *, LAG(drug_day) OVER (PARTITION BY person_id, visit_occurrence_id, drug_concept_id ORDER BY drug_day) AS prev_day_same
  FROM :results_schema.cdc_ase_drug_days
)
SELECT *, CASE WHEN prev_day_same IS NULL OR (drug_day - prev_day_same) > 2 THEN 1 ELSE 0 END AS is_new_antimicrobial
FROM ordered;

DROP TABLE IF EXISTS :results_schema.cdc_ase_presumed_infection;
CREATE TABLE :results_schema.cdc_ase_presumed_infection AS
WITH bc AS (SELECT * FROM :results_schema.cdc_ase_blood_cultures),
qad AS (SELECT * FROM :results_schema.cdc_ase_qad),
first_new_iv AS (
  SELECT bc.person_id, bc.visit_occurrence_id, bc.culture_date, MIN(q.drug_day) AS first_iv_day
  FROM bc JOIN qad q ON q.person_id = bc.person_id AND q.visit_occurrence_id = bc.visit_occurrence_id
    AND q.drug_day BETWEEN bc.culture_date - 2 AND bc.culture_date + 2
    AND q.is_new_antimicrobial = 1 AND q.route_category = 'IV'
  GROUP BY 1,2,3
),
qad_after AS (
  SELECT f.*, COUNT(DISTINCT q.drug_day) AS qad_days, MAX(q.drug_day) AS last_qad
  FROM first_new_iv f
  JOIN qad q ON q.person_id = f.person_id AND q.visit_occurrence_id = f.visit_occurrence_id
    AND q.drug_day BETWEEN f.first_iv_day AND f.first_iv_day + 3
  GROUP BY 1,2,3,4
),
with_outcome AS (
  SELECT qa.*, vo.visit_end_date,
    CASE WHEN vo.visit_end_date <= qa.first_iv_day + INTERVAL '3 days' THEN 1 ELSE 0 END AS early_discharge,
    CASE WHEN vo.discharged_to_concept_id IN (4216643,4216644,322,324,325) THEN 1 ELSE 0 END AS died
  FROM qad_after qa
  JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id = qa.visit_occurrence_id
)
SELECT person_id, visit_occurrence_id, culture_date,
  first_iv_day AS first_qad_date, qad_days AS qad_count,
  last_qad AS last_qad_date, first_iv_day AS first_iv_new_day
FROM with_outcome
WHERE qad_days >= 4 OR (qad_days >= 1 AND (early_discharge = 1 OR died = 1));

CREATE INDEX idx_cdc_ase_pi_person ON :results_schema.cdc_ase_presumed_infection(person_id);
CREATE INDEX idx_cdc_ase_pi_visit ON :results_schema.cdc_ase_presumed_infection(visit_occurrence_id);
