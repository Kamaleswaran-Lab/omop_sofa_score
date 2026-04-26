-- 24-hour rolling urine output - fixed to partition by visit
DROP VIEW IF EXISTS :results_schema.vw_urine_24h CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_urine_24h AS
SELECT 
    person_id,
    visit_occurrence_id,
    measurement_datetime AS charttime,
    value_as_number AS urine_hourly,
    SUM(value_as_number) OVER (
        PARTITION BY person_id, visit_occurrence_id
        ORDER BY measurement_datetime 
        RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
    ) AS urine_24h
FROM (
    SELECT m.person_id, m.measurement_datetime, m.value_as_number, vo.visit_occurrence_id
    FROM :cdm_schema.measurement m
    JOIN :cdm_schema.visit_occurrence vo
      ON m.person_id = vo.person_id
     AND m.measurement_datetime >= vo.visit_start_datetime
     AND m.measurement_datetime <= COALESCE(vo.visit_end_datetime, vo.visit_start_datetime + INTERVAL '30 days')
    WHERE m.measurement_concept_id = 4264378
      AND m.value_as_number IS NOT NULL
) x;
