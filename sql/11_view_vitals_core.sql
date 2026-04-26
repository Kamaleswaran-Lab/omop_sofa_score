-- FIXED: removed >2B local IDs, kept only validated 3024171 and 4196147
CREATE OR REPLACE VIEW :results_schema.view_vitals_core AS
SELECT
  m.person_id,
  m.measurement_datetime,
  MAX(CASE WHEN m.measurement_concept_id = 3024171 THEN m.value_as_number END) AS resp_rate,
  MAX(CASE WHEN m.measurement_concept_id = 4196147 THEN m.value_as_number END) AS spo2,
  MAX(CASE WHEN m.measurement_concept_id = 3027018 THEN m.value_as_number END) AS map
FROM :cdm_schema.measurement m
WHERE m.measurement_concept_id IN (3024171,4196147,3027018)
GROUP BY 1,2;