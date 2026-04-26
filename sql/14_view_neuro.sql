-- FIXED: removed 4254663/4254664 (lymphocyte/lipid), use LOINC GCS codes via join
CREATE OR REPLACE VIEW :results_schema.view_neuro AS
SELECT
  m.person_id,
  m.measurement_datetime,
  MAX(CASE WHEN c.concept_code = '9267-6' THEN m.value_as_number END) AS gcs_eye,
  MAX(CASE WHEN c.concept_code = '9268-4' THEN m.value_as_number END) AS gcs_verbal,
  MAX(CASE WHEN c.concept_code = '9266-8' THEN m.value_as_number END) AS gcs_motor,
  MAX(CASE WHEN c.concept_code = '9269-2' THEN m.value_as_number END) AS gcs_total
FROM :cdm_schema.measurement m
JOIN :vocab_schema.concept c ON c.concept_id = m.measurement_concept_id
WHERE c.vocabulary_id = 'LOINC' AND c.concept_code IN ('9267-6','9268-4','9266-8','9269-2')
GROUP BY 1,2;