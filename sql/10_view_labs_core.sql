CREATE OR REPLACE VIEW results_site_a.vw_labs_core AS
SELECT 
    m.person_id,
    m.measurement_datetime AS charttime,
    MAX(CASE WHEN m.measurement_concept_id IN (3016723, 3051825, 3020564) 
        THEN m.value_as_number END) AS creatinine,
    MAX(CASE WHEN m.measurement_concept_id IN (3024128, 3035616) 
        THEN m.value_as_number END) AS bilirubin,
    MAX(CASE WHEN m.measurement_concept_id IN (3024929, 3013290, 3024386) 
        THEN m.value_as_number END) AS platelets,
    MAX(CASE WHEN m.measurement_concept_id IN (3047181, 3014111) 
        THEN m.value_as_number END) AS lactate
FROM omopcdm.measurement m
WHERE m.measurement_concept_id IN (
    3016723, 3051825, 3020564,
    3024128, 3035616,
    3024929, 3013290, 3024386,
    3047181, 3014111
)
AND m.value_as_number IS NOT NULL
GROUP BY m.person_id, m.measurement_datetime;