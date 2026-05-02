-- 15_view_urine_24h.sql

CREATE OR REPLACE VIEW :results_schema.view_urine_24h AS
SELECT person_id, measurement_datetime,
  SUM(value_as_number) OVER (PARTITION BY person_id ORDER BY measurement_datetime RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW) AS urine_24h_ml
FROM :cdm_schema.measurement m
JOIN :results_schema.concept_set_members cs
  ON cs.concept_id = m.measurement_concept_id
 AND cs.concept_set_name = 'urine_output'
WHERE measurement_datetime IS NOT NULL
  AND value_as_number IS NOT NULL
  AND value_as_number >= 0;
