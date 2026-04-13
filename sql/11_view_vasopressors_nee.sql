CREATE OR REPLACE VIEW results_site_a.vw_vasopressors_nee AS
SELECT 
    d.person_id,
    d.drug_exposure_start_datetime AS charttime,
    d.drug_concept_id,
    d.quantity,
    d.dose_unit_source_value,
    CASE 
        WHEN d.drug_concept_id IN (4328749, 1321341, 19010309) THEN d.quantity * 1.0
        WHEN d.drug_concept_id IN (1338005, 19076899) THEN d.quantity * 1.0
        WHEN d.drug_concept_id IN (1360635, 35202042, 35202043) THEN d.quantity * 2.5
        WHEN d.drug_concept_id IN (1135766, 1335616) THEN d.quantity * 0.1
        WHEN d.drug_concept_id IN (1319998, 1337860) THEN d.quantity * 0.01
        ELSE 0
    END AS nee_dose,
    CASE WHEN d.drug_concept_id IN (1360635, 35202042, 35202043) 
        THEN d.quantity ELSE 0 END AS vasopressin_dose
FROM omopcdm.drug_exposure d
WHERE d.drug_concept_id IN (
    4328749, 1321341, 19010309,
    1338005, 19076899,
    1360635, 35202042, 35202043,
    1135766, 1335616,
    1319998, 1337860
);