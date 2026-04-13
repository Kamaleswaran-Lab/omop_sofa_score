-- PaO2/FiO2 pairs with 240-min window (NO imputation)
DROP VIEW IF EXISTS results_site_a.vw_pao2_fio2_pairs CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_pao2_fio2_pairs AS
WITH pao2 AS (
    SELECT 
        person_id,
        measurement_datetime,
        value_as_number AS pao2,
        measurement_concept_id
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (
        3027315,    -- Oxygen [Partial pressure] in Blood - 7,974 (PRIMARY)
        3039426,    -- O2 sat calc arterial - 1,112
        3011367,    -- O2 sat calc - 10,512
        44786762    -- Mixed venous - 22,775
    )
    AND value_as_number BETWEEN 20 AND 500
),
fio2 AS (
    SELECT 
        person_id,
        measurement_datetime,
        CASE 
            WHEN value_as_number > 1 THEN value_as_number / 100.0 
            ELSE value_as_number 
        END AS fio2,
        measurement_concept_id
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (
        4353936,    -- Inspired O2 concentration - 1,495,269 (PRIMARY)
        3020719,
        3013465
    )
    AND value_as_number BETWEEN 0.21 AND 100
),
spo2 AS (
    SELECT
        person_id,
        measurement_datetime,
        value_as_number AS spo2
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (
        2147483345, -- SpO2 Value - 11,885,033
        4196147     -- Peripheral O2 sat - 5,742,456
    )
    AND value_as_number BETWEEN 0 AND 100
)
SELECT 
    p.person_id,
    p.measurement_datetime AS pao2_time,
    f.measurement_datetime AS fio2_time,
    p.pao2,
    f.fio2,
    p.pao2 / NULLIF(f.fio2, 0) AS pf_ratio,
    s.spo2,
    ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)) / 60) AS delta_minutes,
    p.measurement_concept_id AS pao2_concept_id,
    f.measurement_concept_id AS fio2_concept_id
FROM pao2 p
JOIN fio2 f ON p.person_id = f.person_id
    AND ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)) / 60) <= 240
LEFT JOIN spo2 s ON p.person_id = s.person_id
    AND ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - s.measurement_datetime)) / 60) <= 5;

COMMENT ON VIEW results_site_a.vw_pao2_fio2_pairs IS 'PaO2/FiO2 with 240-min window, no imputation';