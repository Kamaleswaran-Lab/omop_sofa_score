-- Vasopressors with NEE calculation (drug_exposure, not measurement)
DROP VIEW IF EXISTS results_site_a.vw_vasopressors_nee CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_vasopressors_nee AS
SELECT 
    d.person_id,
    d.drug_exposure_start_datetime AS charttime,
    d.drug_exposure_end_datetime,
    d.drug_concept_id,
    d.quantity,
    d.dose_unit_source_value,
    d.route_concept_id,
    -- Norepinephrine equivalents
    CASE 
        WHEN d.drug_concept_id IN (4328749, 1321341, 19010309, 35897581, 4021963) 
            THEN COALESCE(d.quantity, 0) * 1.0
        WHEN d.drug_concept_id IN (1338005, 19076899, 19123434, 35897579, 4022245) 
            THEN COALESCE(d.quantity, 0) * 1.0
        WHEN d.drug_concept_id IN (1360635, 35202042, 35202043, 45775841, 35897584) 
            THEN COALESCE(d.quantity, 0) * 2.5
        WHEN d.drug_concept_id IN (1135766, 1335616, 35897582) 
            THEN COALESCE(d.quantity, 0) * 0.1
        WHEN d.drug_concept_id IN (1319998, 1337860, 40240699, 40240703, 35897578, 4022235) 
            THEN COALESCE(d.quantity, 0) * 0.01
        WHEN d.drug_concept_id IN (1337720, 19076659) 
            THEN COALESCE(d.quantity, 0) * 0.01
        ELSE 0
    END AS nee_dose,
    CASE WHEN d.drug_concept_id IN (1360635, 35202042, 35202043, 45775841, 35897584) 
        THEN d.quantity ELSE 0 END AS vasopressin_dose,
    CASE WHEN d.drug_concept_id IN (1319998, 1337860, 40240699, 40240703, 35897578, 4022235) 
        THEN d.quantity ELSE 0 END AS dopamine_dose,
    CASE WHEN d.drug_concept_id IN (4328749, 1321341, 19010309, 35897581, 4021963) 
        THEN d.quantity ELSE 0 END AS norepi_dose
FROM omopcdm.drug_exposure d
WHERE d.drug_concept_id IN (
    4328749, 1321341, 19010309, 35897581, 4021963,
    1338005, 19076899, 19123434, 35897579, 4022245,
    1360635, 35202042, 35202043, 45775841, 35897584,
    1135766, 1335616, 35897582,
    1319998, 1337860, 40240699, 40240703, 35897578, 4022235,
    1337720, 19076659
)
AND d.quantity IS NOT NULL;

COMMENT ON VIEW results_site_a.vw_vasopressors_nee IS 'Vasopressors with NEE, includes dopamine';