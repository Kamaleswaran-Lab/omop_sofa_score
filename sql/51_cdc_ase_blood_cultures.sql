-- Fix: Uses concept_ancestor to catch all blood cultures and searches both measurement and specimen tables
DROP TABLE IF EXISTS :results_schema.ase_blood_cultures CASCADE;
CREATE TABLE :results_schema.ase_blood_cultures AS
SELECT
  person_id,
  visit_occurrence_id,
  COALESCE(measurement_datetime, measurement_date::timestamp) AS culture_datetime
FROM :cdm_schema.measurement m
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = m.measurement_concept_id
WHERE ca.ancestor_concept_id = 40484543 -- Blood culture ancestor
  AND (m.value_as_concept_id IS NULL OR m.value_as_concept_id != 9189)
UNION
SELECT
  person_id,
  NULL AS visit_occurrence_id,
  COALESCE(specimen_datetime, specimen_date::timestamp) AS culture_datetime
FROM :cdm_schema.specimen s
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = s.specimen_concept_id
WHERE ca.ancestor_concept_id = 40484543;

CREATE INDEX idx_ase_bc_person ON :results_schema.ase_blood_cultures(person_id, culture_datetime);
