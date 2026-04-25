-- PaO2/FiO2 pairing - corrected for variable syntax
DROP VIEW IF EXISTS :results_schema.vw_pao2_fio2_pairs CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_pao2_fio2_pairs AS
WITH pao2 AS (
    SELECT person_id,
           COALESCE(measurement_datetime, measurement_date::timestamp) AS measurement_datetime,
           value_as_number AS pao2
    FROM :cdm_schema.measurement
    WHERE measurement_concept_id IN (3027315)
      AND value_as_number BETWEEN 20 AND 500
),
fio2 AS (
    SELECT person_id,
           COALESCE(measurement_datetime, measurement_date::timestamp) AS measurement_datetime,
           LEAST(GREATEST(CASE WHEN value_as_number > 1 THEN value_as_number/100.0 ELSE value_as_number END, 0.21), 1.0) AS fio2
    FROM :cdm_schema.measurement
    WHERE measurement_concept_id IN (4353936, 3020719, 3013465)
      AND value_as_number BETWEEN 0.21 AND 100
),
paired AS (
    SELECT p.person_id,
           p.measurement_datetime AS pao2_time,
           f.measurement_datetime AS fio2_time,
           p.pao2, f.fio2,
           p.pao2 / NULLIF(f.fio2,0) AS pf_ratio,
           ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime))) AS delta_sec,
           ROW_NUMBER() OVER (PARTITION BY p.person_id, p.measurement_datetime ORDER BY ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime)))) AS rn
    FROM pao2 p
    JOIN fio2 f ON p.person_id = f.person_id
      AND ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime))) <= 14400
)
SELECT person_id, pao2_time, fio2_time, pao2, fio2, pf_ratio, delta_sec/60.0 AS delta_minutes
FROM paired WHERE rn = 1;
