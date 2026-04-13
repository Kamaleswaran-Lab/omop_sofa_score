-- Core labs with SITE_A validated concept IDs
DROP VIEW IF EXISTS results_site_a.vw_labs_core CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_labs_core AS
SELECT 
    m.person_id,
    m.measurement_datetime AS charttime,
    -- Creatinine (renal SOFA) - 549,112 records
    MAX(CASE WHEN m.measurement_concept_id IN (3016723, 3051825, 3020564, 3004327) 
        THEN m.value_as_number END) AS creatinine,
    -- Bilirubin (hepatic SOFA) - 239,317 records
    MAX(CASE WHEN m.measurement_concept_id IN (3024128, 3035616, 3014661) 
        THEN m.value_as_number END) AS bilirubin,
    -- Platelets (coagulation SOFA) - 489,315 records (3024929 PRIMARY)
    MAX(CASE WHEN m.measurement_concept_id IN (3024929, 3024386, 3013290, 3016682) 
        THEN m.value_as_number END) AS platelets,
    -- Lactate - 145,613 total (3047181 + 3014111)
    MAX(CASE WHEN m.measurement_concept_id IN (3047181, 3014111, 3022250, 3008037) 
        THEN m.value_as_number END) AS lactate,
    -- Urine output - 2,203,519 records
    MAX(CASE WHEN m.measurement_concept_id = 4264378 
        THEN m.value_as_number END) AS urine_output
FROM omopcdm.measurement m
WHERE m.measurement_concept_id IN (
    3016723, 3051825, 3020564, 3004327,
    3024128, 3035616, 3014661,
    3024929, 3024386, 3013290, 3016682,
    3047181, 3014111, 3022250, 3008037,
    4264378
)
AND m.value_as_number IS NOT NULL
GROUP BY m.person_id, m.measurement_datetime;

COMMENT ON VIEW results_site_a.vw_labs_core IS 'Core SOFA labs with Site A concept IDs';