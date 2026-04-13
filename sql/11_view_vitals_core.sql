-- Vital signs with SITE_A concept IDs (from top 30 query)
DROP VIEW IF EXISTS results_site_a.vw_vitals_core CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_vitals_core AS
SELECT
    m.person_id,
    m.measurement_datetime AS charttime,
    -- Temperature - 13,155,082 + 1,525,520 = 14.6M
    MAX(CASE WHEN m.measurement_concept_id IN (3020891, 3039856)
        THEN m.value_as_number END) AS temperature,
    -- Heart Rate / Pulse - 3,106,970 + 6,247,867 = 9.3M
    MAX(CASE WHEN m.measurement_concept_id IN (3027018, 4224504)
        THEN m.value_as_number END) AS heart_rate,
    -- Blood Pressure
    MAX(CASE WHEN m.measurement_concept_id = 3004249
        THEN m.value_as_number END) AS sbp,  -- 9,078,063
    MAX(CASE WHEN m.measurement_concept_id = 3012888
        THEN m.value_as_number END) AS dbp,  -- 5,300,302
    MAX(CASE WHEN m.measurement_concept_id IN (4108290, 3027598)
        THEN m.value_as_number END) AS map,  -- 1,027,371
    -- Respiratory Rate - 1,030,420 + 5,010,120 + 1,508,640 = 7.5M
    MAX(CASE WHEN m.measurement_concept_id IN (3024171, 2000000223, 2147483344)
        THEN m.value_as_number END) AS resp_rate,
    -- SpO2 - 11,885,033 + 5,742,456 = 17.6M
    MAX(CASE WHEN m.measurement_concept_id IN (2147483345, 4196147)
        THEN m.value_as_number END) AS spo2
FROM omopcdm.measurement m
WHERE m.measurement_concept_id IN (
    3020891, 3039856,
    3027018, 4224504,
    3004249, 3012888, 4108290, 3027598,
    3024171, 2000000223, 2147483344,
    2147483345, 4196147
)
AND m.value_as_number IS NOT NULL
GROUP BY m.person_id, m.measurement_datetime;

COMMENT ON VIEW results_site_a.vw_vitals_core IS 'Vital signs with Site A concept IDs';