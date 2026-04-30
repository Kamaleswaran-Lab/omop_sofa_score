-- 14_view_neuro.sql
-- MGH patched: adds GCS total concept 4093836
-- Pulls from both observation and measurement (MGH stores in both)

DROP VIEW IF EXISTS :results_schema.vw_neuro CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_neuro AS
WITH neuro_raw AS (
  -- observations
  SELECT
    o.person_id,
    date_trunc('hour', o.observation_datetime) AS charttime,
    o.observation_concept_id AS concept_id,
    AVG(o.value_as_number) AS val
  FROM :cdm_schema.observation o
  WHERE o.observation_concept_id IN (
    4093836,  -- Glasgow coma score (total) - 929k rows
    3016335,  -- GCS eye
    3009094,  -- GCS verbal
    3008223   -- GCS motor
  )
  AND o.observation_datetime IS NOT NULL
  AND o.value_as_number BETWEEN 3 AND 15
  GROUP BY 1,2,3

  UNION ALL

  -- measurements (MGH also stores GCS here)
  SELECT
    m.person_id,
    date_trunc('hour', m.measurement_datetime),
    m.measurement_concept_id,
    AVG(m.value_as_number)
  FROM :cdm_schema.measurement m
  WHERE m.measurement_concept_id IN (4093836,3016335,3009094,3008223)
  AND m.measurement_datetime IS NOT NULL
  AND m.value_as_number BETWEEN 3 AND 15
  GROUP BY 1,2,3
)
SELECT
  person_id,
  charttime,
  MAX(CASE WHEN concept_id = 4093836 THEN val END) AS gcs_total,
  MAX(CASE WHEN concept_id = 3016335 THEN val END) AS gcs_eye,
  MAX(CASE WHEN concept_id = 3009094 THEN val END) AS gcs_verbal,
  MAX(CASE WHEN concept_id = 3008223 THEN val END) AS gcs_motor
FROM neuro_raw
GROUP BY person_id, charttime;
