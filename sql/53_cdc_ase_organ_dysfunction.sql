-- Fix: Resolved Bilirubin vs Lactate fatal error, implemented robust inline concept_ancestor expansions
DROP TABLE IF EXISTS :results_schema.ase_organ_dysfunction CASCADE;
CREATE TABLE :results_schema.ase_organ_dysfunction AS
SELECT
  bc.person_id,
  bc.culture_datetime,
  
  -- Corrected Vasopressor search using descendants
  EXISTS (
    SELECT 1 FROM :cdm_schema.drug_exposure de
    JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
    WHERE ca.ancestor_concept_id IN (1322088, 1343916, 1363053, 1319998, 1360635, 1337720, 35622329)
      AND de.person_id = bc.person_id
      AND de.drug_exposure_start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
  ) AS vaso_init,
  
  -- Corrected Ventilation using descendants across procedures and devices
  EXISTS (
    SELECT 1 FROM :cdm_schema.procedure_occurrence po
    JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = po.procedure_concept_id
    WHERE ca.ancestor_concept_id IN (4049107, 4230167, 45768192)
      AND po.person_id = bc.person_id
      AND po.procedure_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
    UNION ALL
    SELECT 1 FROM :cdm_schema.device_exposure de
    JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.device_concept_id
    WHERE ca.ancestor_concept_id IN (4049107, 4230167, 45768192, 4222965)
      AND de.person_id = bc.person_id
      AND de.device_exposure_start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
  ) AS vent_init,
  
  -- BUG FIX: Lactate (was mistakenly Bilirubin 3024128)
  EXISTS (
    SELECT 1 FROM :cdm_schema.measurement m
    WHERE m.person_id = bc.person_id
      AND m.measurement_concept_id IN (3047181, 3014111, 3022250, 3008037)
      AND m.value_as_number >= 2.0
      AND m.measurement_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
  ) AS lactate_high
  
FROM :results_schema.ase_blood_cultures bc;
