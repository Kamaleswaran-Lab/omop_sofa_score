-- Core labs with SITE_A validated concept IDs
-- Fixed: uses variables, unit conversion for creatinine
DROP VIEW IF EXISTS :results_schema.vw_labs_core CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_labs_core AS
SELECT 
    m.person_id,
    m.measurement_datetime AS charttime,
    -- Creatinine (renal SOFA) - convert umol/L to mg/dL
    MAX(CASE 
        WHEN m.measurement_concept_id IN (3016723, 3051825) THEN m.value_as_number -- assumed mg/dL
        WHEN m.measurement_concept_id IN (3020564, 3004327) THEN m.value_as_number / 88.4 -- umol/L -> mg/dL
    END) AS creatinine,
    -- Bilirubin (hepatic SOFA)
    MAX(CASE WHEN m.measurement_concept_id IN (3024128, 3035616, 3014661) 
        THEN m.value_as_number END) AS bilirubin,
    -- Platelets (coagulation SOFA)
    MAX(CASE WHEN m.measurement_concept_id IN (3024929, 3013290, 3016682) 
        THEN m.value_as_number END) AS platelets,
    -- Lactate
    MAX(CASE WHEN m.measurement_concept_id IN (3047181, 3014111, 3008037) 
        THEN m.value_as_number END) AS lactate,
    -- Urine output
    MAX(CASE WHEN m.measurement_concept_id = 4264378 
        THEN m.value_as_number END) AS urine_output
FROM :cdm_schema.measurement m
WHERE m.measurement_concept_id IN (
    3016723, 3051825, 3020564, 3004327,
    3024128, 3035616, 3014661,
    3024929, 3013290, 3016682,
    3047181, 3014111, 3008037,
    4264378
)
AND m.value_as_number IS NOT NULL
GROUP BY m.person_id, m.measurement_datetime;

COMMENT ON VIEW :results_schema.vw_labs_core IS 'Core SOFA labs with unit normalization';
