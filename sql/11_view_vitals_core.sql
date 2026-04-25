-- Vitals
CREATE OR REPLACE VIEW :results_schema.view_vitals_core AS
SELECT
  m.person_id,
  m.measurement_datetime,
  c.concept_name,
  m.value_as_number
FROM :cdm_schema.measurement m
JOIN :vocab_schema.concept c ON c.concept_id = m.measurement_concept_id
WHERE c.concept_id IN (3027018, 3019962, 3027590); -- MAP, SBP, DBP
