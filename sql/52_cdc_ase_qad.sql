-- 52_cdc_ase_qad.sql
-- FIX: handle NULL days_supply
DROP TABLE IF EXISTS :results_schema.ase_qad CASCADE;
CREATE TABLE :results_schema.ase_qad AS
WITH abx AS (
  SELECT de.person_id, de.visit_occurrence_id,
         COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_dt,
         COALESCE(de.drug_exposure_end_datetime,
                  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) + COALESCE(de.days_supply,1) * INTERVAL '1 day'
         ) AS end_dt
  FROM :cdm_schema.drug_exposure de
  JOIN :results_schema.assumptions a ON a.domain='antibiotic' AND a.concept_id = de.drug_concept_id
),
days AS (
  SELECT person_id, visit_occurrence_id, generate_series(start_dt::date, end_dt::date, '1 day')::date AS d
  FROM abx
)
SELECT person_id, visit_occurrence_id, MIN(d) AS qad_start, MAX(d) AS qad_end, COUNT(*) AS qad_days
FROM days
GROUP BY person_id, visit_occurrence_id, d - (ROW_NUMBER() OVER (PARTITION BY person_id, visit_occurrence_id ORDER BY d))::int
HAVING COUNT(*) >= (SELECT qad_min_days FROM :results_schema.ase_parameters);
