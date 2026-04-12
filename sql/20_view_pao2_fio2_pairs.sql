-- OMOP SOFA v4.4 - PaO2/FiO2 pairing
-- FIX #2: NO imputation (must have real FiO2)
-- FIX #3: 240-minute window (was 120)

DROP VIEW IF EXISTS results.v_pao2_fio2_pairs CASCADE;

CREATE VIEW results.v_pao2_fio2_pairs AS
WITH pao2_measurements AS (
    SELECT 
        person_id, 
        measurement_datetime, 
        value_as_number AS pao2,
        unit_concept_id
    FROM results.v_labs_core 
    WHERE lab_type = 'pao2'
    AND value_as_number BETWEEN 20 AND 700  -- Valid range
),
fio2_measurements AS (
    SELECT 
        person_id, 
        measurement_datetime,
        -- Convert % to fraction if needed
        CASE 
            WHEN value_as_number > 1 THEN value_as_number / 100.0 
            ELSE value_as_number 
        END AS fio2,
        value_as_number AS fio2_raw
    FROM results.v_labs_core 
    WHERE lab_type = 'fio2'
    AND value_as_number IS NOT NULL  -- FIX #2: Must have real value
    AND value_as_number BETWEEN 0.21 AND 100  -- Valid range
)
SELECT
    p.person_id,
    p.measurement_datetime AS pao2_time,
    p.pao2,
    f.measurement_datetime AS fio2_time,
    f.fio2,
    f.fio2_raw,
    ABS(EXTRACT(EPOCH FROM (f.measurement_datetime - p.measurement_datetime)) / 60) AS delta_minutes,
    p.pao2 / NULLIF(f.fio2, 0) AS pf_ratio,
    
    -- Window check (FIX #3: 240 minutes, not 120)
    CASE 
        WHEN ABS(EXTRACT(EPOCH FROM (f.measurement_datetime - p.measurement_datetime)) / 60) <= 240 
        THEN TRUE 
        ELSE FALSE 
    END AS within_240min_window,
    
    -- Quality flags
    CASE 
        WHEN f.fio2 BETWEEN 0.21 AND 0.25 THEN 'room_air'
        WHEN f.fio2 BETWEEN 0.26 AND 0.40 THEN 'low_oxygen'
        WHEN f.fio2 BETWEEN 0.41 AND 0.60 THEN 'moderate_oxygen'
        WHEN f.fio2 > 0.60 THEN 'high_oxygen'
    END AS fio2_category

FROM pao2_measurements p
JOIN fio2_measurements f 
    ON p.person_id = f.person_id
    AND ABS(EXTRACT(EPOCH FROM (f.measurement_datetime - p.measurement_datetime)) / 60) <= 240  -- FIX #3
WHERE f.fio2 IS NOT NULL  -- FIX #2: NO imputation
    AND f.fio2 >= 0.21
    AND p.pao2 / NULLIF(f.fio2, 0) BETWEEN 20 AND 800;  -- Valid PF ratio range

COMMENT ON VIEW results.v_pao2_fio2_pairs IS 'PaO2/FiO2 pairs - 240min window, no imputation';

SELECT 'PaO2/FiO2 pairs created (FIX #2, #3)' AS status;
