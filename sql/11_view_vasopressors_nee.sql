CREATE OR REPLACE VIEW results_site_a.vw_vasopressors_nee AS
SELECT 
    d.person_id,
    d.drug_exposure_start_datetime AS charttime,
    d.drug_concept_id,
    d.quantity,
    CASE 
        WHEN d.drug_concept_id IN (4328749, 1321341) THEN d.quantity * 1.0
        WHEN d.drug_concept_id = 1338005 THEN d.quantity * 1.0
        WHEN d.drug_concept_id = 1360635 THEN d.quantity * 2.5
        WHEN d.drug_concept_id = 1335616 THEN d.quantity * 0.1
        WHEN d.drug_concept_id = 1319998 THEN d.quantity * 0.01
        ELSE 0
    END AS nee_dose,
    CASE WHEN d.drug_concept_id = 1360635 THEN d.quantity ELSE 0 END AS vasopressin_dose
FROM omopcdm.drug_exposure d
WHERE d.drug_concept_id IN (
    4328749, 1321341, 1338005, 1360635, 1335616, 1319998, 1337860
);