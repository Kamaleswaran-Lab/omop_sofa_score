CREATE OR REPLACE VIEW results_site_a.vw_pao2_fio2_pairs AS
WITH pao2 AS (
    SELECT 
        person_id,
        measurement_datetime,
        value_as_number AS pao2
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (3027315, 3039426, 3011367, 44786762)
    AND value_as_number BETWEEN 20 AND 500
),
fio2 AS (
    SELECT 
        person_id,
        measurement_datetime,
        CASE 
            WHEN value_as_number > 1 THEN value_as_number / 100.0 
            ELSE value_as_number 
        END AS fio2
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (4353936, 3020719, 3013465)
    AND value_as_number BETWEEN 0.21 AND 100
)
SELECT 
    p.person_id,
    p.measurement_datetime AS pao2_time,
    f.measurement_datetime AS fio2_time,
    p.pao2,
    f.fio2,
    p.pao2 / NULLIF(f.fio2, 0) AS pf_ratio,
    ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)) / 60) AS delta_minutes
FROM pao2 p
JOIN fio2 f ON p.person_id = f.person_id
    AND ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)) / 60) <= 240;