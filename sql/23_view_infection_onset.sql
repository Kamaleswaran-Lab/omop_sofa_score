-- Suspected infection onset (antibiotics + culture)
DROP VIEW IF EXISTS results_site_a.vw_infection_onset CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_infection_onset AS
SELECT 
    a.person_id,
    a.drug_exposure_start_datetime AS infection_onset,
    MIN(c.specimen_datetime) AS culture_time,
    a.drug_concept_id AS antibiotic_concept_id,
    a.drug_name AS antibiotic_name
FROM results_site_a.vw_antibiotics a
JOIN results_site_a.vw_cultures c ON a.person_id = c.person_id
    AND c.specimen_datetime BETWEEN 
        a.drug_exposure_start_datetime - INTERVAL '24 hours'
        AND a.drug_exposure_start_datetime + INTERVAL '72 hours'
GROUP BY a.person_id, a.drug_exposure_start_datetime, a.drug_concept_id, a.drug_name;