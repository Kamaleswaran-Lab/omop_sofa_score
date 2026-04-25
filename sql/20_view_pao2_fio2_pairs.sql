-- PaO2/FiO2 pairing
-- FIX: expand window to 4h
CREATE OR REPLACE VIEW :results_schema.view_pao2_fio2_pairs AS
SELECT
  p.person_id,
  p.measurement_datetime AS pao2_time,
  p.value_as_number AS pao2,
  f.value_as_number AS fio2,
  p.value_as_number / NULLIF(f.value_as_number/100.0,0) AS pf_ratio
FROM :cdm_schema.measurement p
JOIN :cdm_schema.measurement f 
  ON f.person_id = p.person_id
 AND ABS(EXTRACT(EPOCH FROM (f.measurement_datetime - p.measurement_datetime))/3600) <= 4
WHERE p.measurement_concept_id = 3004249 -- PaO2
  AND f.measurement_concept_id = 3020714; -- FiO2
