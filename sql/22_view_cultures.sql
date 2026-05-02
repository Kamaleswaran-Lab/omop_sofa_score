DROP VIEW IF EXISTS :results_schema.view_cultures CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_cultures AS
WITH meas_cult AS (
  SELECT
    m.person_id,
    m.measurement_id AS specimen_id,
    COALESCE(m.measurement_datetime, m.measurement_date::timestamp) AS specimen_datetime,
    m.measurement_concept_id AS source_concept_id,
    m.visit_occurrence_id
  FROM :cdm_schema.measurement m
  JOIN :results_schema.concept_set_members cs
    ON cs.concept_id = m.measurement_concept_id
   AND cs.concept_set_name = 'culture_measurement'
),
spec_cult AS (
  SELECT
    s.person_id,
    s.specimen_id,
    COALESCE(s.specimen_datetime, s.specimen_date::timestamp) AS specimen_datetime,
    s.specimen_concept_id AS source_concept_id,
    NULL::bigint AS visit_occurrence_id   -- your CDM has no column
  FROM :cdm_schema.specimen s
  JOIN :results_schema.concept_set_members cs
    ON cs.concept_id = s.specimen_concept_id
   AND cs.concept_set_name = 'culture_specimen'
),
proc_cult AS (
  SELECT
    po.person_id,
    po.procedure_occurrence_id AS specimen_id,
    COALESCE(po.procedure_datetime, po.procedure_date::timestamp) AS specimen_datetime,
    po.procedure_concept_id AS source_concept_id,
    po.visit_occurrence_id
  FROM :cdm_schema.procedure_occurrence po
  WHERE po.procedure_source_value ILIKE '%blood culture%'
     OR po.procedure_concept_id IN (
       SELECT concept_id FROM :vocab_schema.concept
       WHERE concept_name ILIKE '%blood culture%' AND domain_id='Procedure'
     )
)
SELECT DISTINCT ON (person_id, specimen_id, specimen_datetime)
  person_id,
  specimen_id,
  specimen_datetime,
  source_concept_id,
  visit_occurrence_id
FROM (
  SELECT * FROM meas_cult
  UNION ALL SELECT * FROM spec_cult
  UNION ALL SELECT * FROM proc_cult
) u
WHERE specimen_datetime IS NOT NULL
ORDER BY person_id, specimen_id, specimen_datetime;
