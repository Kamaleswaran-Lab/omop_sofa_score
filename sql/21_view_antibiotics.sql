CREATE OR REPLACE VIEW :results_schema.view_antibiotics AS
SELECT de.person_id, de.drug_exposure_start_datetime FROM :cdm_schema.drug_exposure de
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
WHERE ca.ancestor_concept_id = 21602796;