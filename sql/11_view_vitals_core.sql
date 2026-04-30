-- 11_view_vitals_core.sql
-- MGH patched: adds invasive + non-invasive MAP
-- Original repo: Kamaleswaran-Lab/omop_sofa_score

DROP VIEW IF EXISTS :results_schema.vw_vitals_core CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_vitals_core AS
WITH vitals AS (
  SELECT
    m.person_id,
    date_trunc('hour', m.measurement_datetime) AS charttime,
    m.measurement_concept_id,
    AVG(m.value_as_number) AS val
  FROM :cdm_schema.measurement m
  WHERE m.measurement_concept_id IN (
    4108290,  -- Invasive mean arterial pressure (MGH: 1,027,371 rows)
    3027597,  -- Mean arterial pressure
    3019962,  -- MAP (legacy)
    3034703,  -- Systolic BP (kept for completeness)
    3027598,  -- Diastolic BP
    3027018   -- Heart rate
  )
  AND m.measurement_datetime IS NOT NULL
  AND m.value_as_number BETWEEN 0 AND 300
  GROUP BY 1,2,3
)
SELECT
  person_id,
  charttime,
  MAX(CASE WHEN measurement_concept_id IN (4108290,3027597,3019962) THEN val END) AS map,
  MAX(CASE WHEN measurement_concept_id = 3034703 THEN val END) AS sbp,
  MAX(CASE WHEN measurement_concept_id = 3027598 THEN val END) AS dbp,
  MAX(CASE WHEN measurement_concept_id = 3027018 THEN val END) AS heart_rate
FROM vitals
GROUP BY person_id, charttime;
