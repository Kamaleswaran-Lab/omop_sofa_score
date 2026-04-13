-- Antibiotics for sepsis detection
DROP VIEW IF EXISTS results_site_a.vw_antibiotics CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_antibiotics AS
SELECT 
    d.person_id,
    d.drug_exposure_start_datetime,
    d.drug_exposure_end_datetime,
    d.drug_concept_id,
    c.concept_name AS drug_name
FROM omopcdm.drug_exposure d
JOIN omopcdm.vocabulary.concept_ancestor ca ON d.drug_concept_id = ca.descendant_concept_id
JOIN omopcdm.vocabulary.concept c ON d.drug_concept_id = c.concept_id
WHERE ca.ancestor_concept_id = 21600381;  -- Antibiotic ancestor