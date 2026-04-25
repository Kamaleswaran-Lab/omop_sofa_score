-- GCS components
CREATE OR REPLACE VIEW :results_schema.view_neuro AS
SELECT
  m.person_id,
  m.measurement_datetime,
  MAX(CASE WHEN c.concept_id = 4254662 THEN m.value_as_number END) AS gcs_eye,
  MAX(CASE WHEN c.concept_id = 4254663 THEN m.value_as_number END) AS gcs_verbal,
  MAX(CASE WHEN c.concept_id = 4254664 THEN m.value_as_number END) AS gcs_motor
FROM :cdm_schema.measurement m
JOIN :vocab_schema.concept c ON c.concept_id = m.measurement_concept_id
WHERE c.concept_id IN (4254662,4254663,4254664)
GROUP BY 1,2;
