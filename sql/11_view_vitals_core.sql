-- Vital signs with SITE_A concept IDs
DROP VIEW IF EXISTS :results_schema.vw_vitals_core CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_vitals_core AS
WITH base AS (
  SELECT
      m.person_id,
      m.measurement_datetime AS charttime,
      MAX(CASE WHEN m.measurement_concept_id IN (3020891, 3039856) THEN m.value_as_number END) AS temperature,
      MAX(CASE WHEN m.measurement_concept_id IN (3027018, 4224504) THEN m.value_as_number END) AS heart_rate,
      MAX(CASE WHEN m.measurement_concept_id = 3004249 THEN m.value_as_number END) AS sbp,
      MAX(CASE WHEN m.measurement_concept_id = 3012888 THEN m.value_as_number END) AS dbp,
      MAX(CASE WHEN m.measurement_concept_id IN (4108290, 3027598) THEN m.value_as_number END) AS map_measured,
      MAX(CASE WHEN m.measurement_concept_id IN (3024171, 4313590) THEN m.value_as_number END) AS resp_rate,
      MAX(CASE WHEN m.measurement_concept_id IN (4196147, 4310550) THEN m.value_as_number END) AS spo2
  FROM :cdm_schema.measurement m
  WHERE m.measurement_concept_id IN (
      3020891, 3039856,
      3027018, 4224504,
      3004249, 3012888, 4108290, 3027598,
      3024171, 4313590,
      4196147, 4310550
  )
  AND m.value_as_number IS NOT NULL
  GROUP BY m.person_id, m.measurement_datetime
)
SELECT 
  person_id, charttime, temperature, heart_rate, sbp, dbp,
  COALESCE(map_measured, (sbp + 2.0*dbp)/3.0) AS map,
  resp_rate, spo2
FROM base;

COMMENT ON VIEW :results_schema.vw_vitals_core IS 'Vital signs with MAP fallback calculation';
