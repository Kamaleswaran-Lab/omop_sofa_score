-- FIXED: removed 3013290 (CO2), kept only real platelets 3024929,3016682
CREATE OR REPLACE VIEW :results_schema.view_labs_core AS
SELECT
  m.person_id,
  m.measurement_datetime,
  MAX(CASE WHEN m.measurement_concept_id IN (3024929, 3016682) THEN m.value_as_number END) AS platelets,
  MAX(CASE WHEN m.measurement_concept_id IN (3047181, 3014111, 3008037) THEN m.value_as_number END) AS lactate,
  MAX(CASE WHEN m.measurement_concept_id = 3013682 THEN 
    CASE WHEN m.unit_concept_id = 8753 THEN m.value_as_number/17.1 ELSE m.value_as_number END END) AS bilirubin,
  MAX(CASE WHEN m.measurement_concept_id = 3016723 THEN 
    CASE WHEN m.unit_concept_id = 8753 THEN m.value_as_number/88.4 ELSE m.value_as_number END END) AS creatinine
FROM :cdm_schema.measurement m
WHERE m.measurement_concept_id IN (3024929,3016682,3047181,3014111,3008037,3013682,3016723)
GROUP BY 1,2;