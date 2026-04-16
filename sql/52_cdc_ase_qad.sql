-- 52_cdc_ase_qad.sql
-- PURPOSE: Calculate Qualifying Antibiotic Days (QAD)
-- FIXES: handle NULL days_supply and end dates

DROP TABLE IF EXISTS omop_cdm.ase_qad CASCADE;
CREATE TABLE omop_cdm.ase_qad AS
WITH abx AS (
  SELECT
    de.person_id,
    de.visit_occurrence_id,
    COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_dt,
    COALESCE(
      de.drug_exposure_end_datetime,
      de.drug_exposure_start_datetime + COALESCE(de.days_supply, 1) * INTERVAL '1 day'
    ) AS end_dt
  FROM omop_cdm.drug_exposure de
  JOIN omop_sofa.assumptions a ON a.domain='antibiotic' AND a.concept_id = de.drug_concept_id
),
days AS (
  SELECT person_id, visit_occurrence_id, generate_series(start_dt::date, end_dt::date, '1 day')::date AS abx_day
  FROM abx
),
grouped AS (
  SELECT person_id, visit_occurrence_id, abx_day,
         abx_day - ROW_NUMBER() OVER (PARTITION BY person_id, visit_occurrence_id ORDER BY abx_day) * INTERVAL '1 day' AS grp
  FROM days
)
SELECT person_id, visit_occurrence_id, MIN(abx_day) AS qad_start, MAX(abx_day) AS qad_end, COUNT(*) AS qad_days
FROM grouped
GROUP BY person_id, visit_occurrence_id, grp
HAVING COUNT(*) >= (SELECT qad_min_days FROM omop_sofa.ase_parameters)
;
