-- OMOP SOFA v4.4 - 24-hour urine output
-- FIX #6: Rolling 24h window (not hourly snapshots)

DROP VIEW IF EXISTS results.v_urine_24h CASCADE;

CREATE VIEW results.v_urine_24h AS
SELECT
    person_id,
    measurement_datetime,
    value_as_number AS urine_volume_ml,
    unit_concept_id,
    
    -- Rolling 24-hour sum
    SUM(value_as_number) OVER (
        PARTITION BY person_id 
        ORDER BY measurement_datetime 
        RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
    ) AS urine_24h_rolling_ml,
    
    -- Count of measurements in window
    COUNT(*) OVER (
        PARTITION BY person_id 
        ORDER BY measurement_datetime 
        RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
    ) AS measurements_in_24h,
    
    -- Time since first measurement in window
    EXTRACT(EPOCH FROM (
        measurement_datetime - 
        MIN(measurement_datetime) OVER (
            PARTITION BY person_id 
            ORDER BY measurement_datetime 
            RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
        )
    )) / 3600 AS hours_of_data

FROM cdm.measurement
WHERE measurement_concept_id IN (
    SELECT descendant_concept_id 
    FROM vocab.concept_ancestor 
    WHERE ancestor_concept_id = 4065485  -- Urine output
)
AND value_as_number IS NOT NULL
AND value_as_number >= 0
AND value_as_number < 10000;  -- Sanity check

COMMENT ON VIEW results.v_urine_24h IS 'Rolling 24h urine output for renal SOFA';

SELECT 'Urine 24h view created (FIX #6)' AS status;
