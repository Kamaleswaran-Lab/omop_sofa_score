
-- 51_cdc_ase_blood_cultures.sql
-- Identify blood culture dates per CDC ASE
-- Uses existing view from omop_sofa_score if present: results_schema.view_cultures

DROP TABLE IF EXISTS :results_schema.cdc_ase_blood_cultures;
CREATE TABLE :results_schema.cdc_ase_blood_cultures AS
WITH bc AS (
  SELECT 
    m.person_id,
    vo.visit_occurrence_id,
    DATE(m.measurement_date) AS culture_date,
    m.measurement_datetime
  FROM :cdm_schema.measurement m
  JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id = m.visit_occurrence_id
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_blood_culture_concepts)
  UNION ALL
  SELECT 
    p.person_id,
    p.visit_occurrence_id,
    DATE(p.procedure_date) AS culture_date,
    p.procedure_datetime AS measurement_datetime
  FROM :cdm_schema.procedure_occurrence p
  JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id = p.visit_occurrence_id
  WHERE p.procedure_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_blood_culture_concepts)
)
SELECT DISTINCT person_id, visit_occurrence_id, culture_date, MIN(measurement_datetime) AS first_culture_datetime
FROM bc
GROUP BY person_id, visit_occurrence_id, culture_date;
