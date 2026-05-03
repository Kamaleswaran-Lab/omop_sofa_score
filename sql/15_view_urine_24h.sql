-- sql/15_view_urine_24h.sql
-- Rolling 24-hour urine sum with "sparse charting" protections.

CREATE OR REPLACE VIEW :results_schema.view_urine_24h AS
WITH rolling_calc AS (
  SELECT 
    person_id, 
    measurement_datetime,
    SUM(value_as_number) OVER (
      PARTITION BY person_id 
      ORDER BY measurement_datetime 
      RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
    ) AS urine_24h_ml,
    COUNT(value_as_number) OVER (
      PARTITION BY person_id 
      ORDER BY measurement_datetime 
      RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
    ) AS measurement_count
  FROM :cdm_schema.measurement m
  JOIN :results_schema.concept_set_members cs
    ON cs.concept_id = m.measurement_concept_id
   AND cs.concept_set_name = 'urine_output'
  WHERE measurement_datetime IS NOT NULL
    AND value_as_number IS NOT NULL
    AND value_as_number >= 0
)
SELECT person_id, measurement_datetime, urine_24h_ml
FROM rolling_calc
-- The Fix: Ignore sparse charting. If they peed > 500 they are safe anyway.
-- If < 500, we only trust it if the nurses charted at least 3 distinct times.
WHERE measurement_count >= 3 OR urine_24h_ml >= 500;
