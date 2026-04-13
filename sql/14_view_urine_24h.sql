CREATE OR REPLACE VIEW results_site_a.vw_urine_24h AS
SELECT person_id, measurement_datetime AS charttime,
    SUM(value_as_number) OVER (
        PARTITION BY person_id 
        ORDER BY measurement_datetime 
        RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
    ) AS urine_24h
FROM omopcdm.measurement
WHERE measurement_concept_id = 4264378;