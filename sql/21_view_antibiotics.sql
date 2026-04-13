CREATE OR REPLACE VIEW results_site_a.vw_antibiotics AS
SELECT d.person_id, d.drug_exposure_start_datetime, d.drug_concept_id
FROM omopcdm.drug_exposure d
JOIN vocabulary.concept_ancestor ca ON d.drug_concept_id = ca.descendant_concept_id
WHERE ca.ancestor_concept_id = 21600381;