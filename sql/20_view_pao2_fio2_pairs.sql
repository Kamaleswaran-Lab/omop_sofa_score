-- CORRECTED for MGH/CHoRUS: prevents Cartesian explosion by picking closest FiO2
DROP VIEW IF EXISTS {{results_schema}}.vw_pao2_fio2_pairs CASCADE;

CREATE OR REPLACE VIEW {{results_schema}}.vw_pao2_fio2_pairs AS
WITH pao2 AS (
    SELECT 
        person_id,
        COALESCE(measurement_datetime, measurement_date::timestamp) AS measurement_datetime,
        value_as_number AS pao2,
        measurement_concept_id
    FROM {{cdm_schema}}.measurement
    WHERE measurement_concept_id IN (3027315, 3039426, 3011367, 44786762) -- PaO2
      AND value_as_number BETWEEN 20 AND 500
),
fio2 AS (
    SELECT 
        person_id,
        COALESCE(measurement_datetime, measurement_date::timestamp) AS measurement_datetime,
        LEAST(GREATEST(
            CASE WHEN value_as_number > 1 THEN value_as_number / 100.0 ELSE value_as_number END,
        0.21), 1.0) AS fio2,
        measurement_concept_id
    FROM {{cdm_schema}}.measurement
    WHERE measurement_concept_id IN (4353936, 3020719, 3013465) -- FiO2
      AND value_as_number BETWEEN 0.21 AND 100
),
spo2 AS (
    SELECT 
        person_id,
        COALESCE(measurement_datetime, measurement_date::timestamp) AS measurement_datetime,
        value_as_number AS spo2
    FROM {{cdm_schema}}.measurement
    WHERE measurement_concept_id IN (2147483345, 4196147) -- SpO2
      AND value_as_number BETWEEN 0 AND 100
),
paired AS (
    SELECT 
        p.person_id,
        p.measurement_datetime AS pao2_time,
        f.measurement_datetime AS fio2_time,
        p.pao2,
        f.fio2,
        p.pao2 / NULLIF(f.fio2, 0) AS pf_ratio,
        ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)) / 60.0) AS delta_minutes,
        p.measurement_concept_id AS pao2_concept_id,
        f.measurement_concept_id AS fio2_concept_id,
        ROW_NUMBER() OVER (
            PARTITION BY p.person_id, p.measurement_datetime
            ORDER BY ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)))
        ) AS rn_fio2
    FROM pao2 p
    JOIN fio2 f ON p.person_id = f.person_id
        AND ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime))) <= 14400 -- 240 min
)
SELECT 
    pr.person_id,
    pr.pao2_time,
    pr.fio2_time,
    pr.pao2,
    pr.fio2,
    pr.pf_ratio,
    s.spo2,
    pr.delta_minutes,
    pr.pao2_concept_id,
    pr.fio2_concept_id
FROM paired pr
LEFT JOIN spo2 s ON pr.person_id = s.person_id
    AND ABS(EXTRACT(EPOCH FROM (pr.pao2_time - s.measurement_datetime))) <= 300 -- 5 min
WHERE pr.rn_fio2 = 1;
