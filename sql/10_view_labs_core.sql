-- Core labs with unit conversion
-- FIX: convert umol/L to mg/dL for bilirubin, creatinine
CREATE OR REPLACE VIEW :results_schema.view_labs_core AS
SELECT
  m.person_id,
  m.measurement_datetime,
  c.concept_code AS lab_code,
  CASE 
    WHEN c.concept_id = 3013682 AND m.unit_concept_id = 8753 THEN m.value_as_number / 17.1 -- bilirubin umol/L -> mg/dL
    WHEN c.concept_id = 3016723 AND m.unit_concept_id = 8753 THEN m.value_as_number / 88.4 -- creatinine umol/L -> mg/dL
    ELSE m.value_as_number
  END AS value_corrected
FROM :cdm_schema.measurement m
JOIN :vocab_schema.concept c ON c.concept_id = m.measurement_concept_id
WHERE c.concept_id IN (3013682, 3016723, 3013650, 3024561) -- bili, creat, platelets, etc.
  AND m.value_as_number IS NOT NULL;
