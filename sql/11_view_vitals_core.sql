-- 11_view_vitals_core.sql
-- Core vital signs, using canonical concept sets.

DROP VIEW IF EXISTS :results_schema.vw_vitals_core CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_vitals_core AS
WITH vitals AS (
  SELECT
    m.person_id,
    date_trunc('hour', m.measurement_datetime) AS charttime,
    m.measurement_concept_id,
    AVG(m.value_as_number) AS val
  FROM :cdm_schema.measurement m
  JOIN :results_schema.concept_set_members cs
    ON cs.concept_id = m.measurement_concept_id
   AND cs.concept_set_name IN ('map', 'sbp', 'dbp', 'heart_rate')
  WHERE m.measurement_datetime IS NOT NULL
    AND m.value_as_number BETWEEN 0 AND 300
  GROUP BY 1,2,3
)
SELECT
  person_id,
  charttime,
  MAX(CASE WHEN measurement_concept_id IN (
    SELECT concept_id FROM :results_schema.concept_set_members WHERE concept_set_name = 'map'
  ) THEN val END) AS map,
  MAX(CASE WHEN measurement_concept_id IN (
    SELECT concept_id FROM :results_schema.concept_set_members WHERE concept_set_name = 'sbp'
  ) THEN val END) AS sbp,
  MAX(CASE WHEN measurement_concept_id IN (
    SELECT concept_id FROM :results_schema.concept_set_members WHERE concept_set_name = 'dbp'
  ) THEN val END) AS dbp,
  MAX(CASE WHEN measurement_concept_id IN (
    SELECT concept_id FROM :results_schema.concept_set_members WHERE concept_set_name = 'heart_rate'
  ) THEN val END) AS heart_rate
FROM vitals
GROUP BY person_id, charttime;
