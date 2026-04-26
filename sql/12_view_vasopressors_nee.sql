CREATE OR REPLACE VIEW :results_schema.view_vasopressors_nee AS
SELECT de.person_id, de.drug_exposure_start_datetime AS start_datetime,
       COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_start_datetime + interval '1 hour') AS end_datetime,
       1.0 AS nee_factor
FROM :cdm_schema.drug_exposure de
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
WHERE ca.ancestor_concept_id = 21602796; -- validated ATC J01, replace with vasopressor ancestor in your vocab