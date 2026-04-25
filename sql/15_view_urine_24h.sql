-- 24h urine output
-- FIX: use measurement_datetime not date
CREATE OR REPLACE VIEW :results_schema.view_urine_24h AS
SELECT
  person_id,
  measurement_datetime,
  SUM(value_as_number) OVER (
    PARTITION BY person_id 
    ORDER BY measurement_datetime 
    RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW
  ) AS urine_24h_ml
FROM :cdm_schema.measurement
WHERE measurement_concept_id = 3016723; -- urine output concept example
