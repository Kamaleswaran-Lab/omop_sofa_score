-- FIXED: supports cultures in specimen OR measurement (or both)
CREATE OR REPLACE VIEW :results_schema.view_cultures AS
WITH meas_cult AS (
  SELECT 
    m.person_id,
    m.measurement_datetime AS specimen_datetime,
    m.measurement_concept_id AS source_concept_id
  FROM :cdm_schema.measurement m
  WHERE m.measurement_concept_id IN (
    3023368, 3013867, 3026008, 3025099, 3039355,
    40762243, 3003714, 3000494, 3005702, 3025941,
    3011298, 3016727, 3027005, 3016114, 3016914, 3015479,
    3045330, 40765191, 3037692, 3023419  -- expanded from prior list
  )
),
spec_cult AS (
  SELECT 
    s.person_id,
    s.specimen_datetime,
    s.specimen_concept_id AS source_concept_id
  FROM :cdm_schema.specimen s
  WHERE s.specimen_concept_id IN (
    618898, 1447635, 3516065, 3667301, 3667306  -- validated specimen IDs
  )
),
proc_cult AS (
  SELECT 
    po.person_id,
    po.procedure_datetime AS specimen_datetime,
    po.procedure_concept_id AS source_concept_id
  FROM :cdm_schema.procedure_occurrence po
  WHERE po.procedure_concept_id IN (
    SELECT concept_id FROM :vocab_schema.concept
    WHERE LOWER(concept_name) LIKE '%blood culture%' AND domain_id = 'Procedure'
  )
)
SELECT DISTINCT person_id, specimen_datetime, source_concept_id
FROM (
  SELECT * FROM meas_cult
  UNION ALL
  SELECT * FROM spec_cult
  UNION ALL
  SELECT * FROM proc_cult
) all_cult;
