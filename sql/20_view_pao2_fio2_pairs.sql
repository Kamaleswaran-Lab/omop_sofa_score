-- 20_view_pao2_fio2_pairs.sql
-- Generalized PaO2/FiO2 pairing using canonical concept sets.

DROP VIEW IF EXISTS :results_schema.view_pao2_fio2_pairs CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_pao2_fio2_pairs AS
WITH
pao2 AS (
  SELECT
    m.person_id,
    m.measurement_datetime AS t,
    m.value_as_number AS pao2
  FROM :cdm_schema.measurement m
  JOIN :results_schema.concept_set_members pc
    ON pc.concept_id = m.measurement_concept_id
   AND pc.concept_set_name = 'pao2'
  WHERE m.value_as_number BETWEEN 20 AND 800
    AND m.measurement_datetime IS NOT NULL
    AND m.value_as_number IS NOT NULL
  UNION ALL
  SELECT
    o.person_id,
    o.observation_datetime AS t,
    o.value_as_number AS pao2
  FROM :cdm_schema.observation o
  JOIN :results_schema.concept_set_members pc
    ON pc.concept_id = o.observation_concept_id
   AND pc.concept_set_name = 'pao2'
  WHERE o.value_as_number BETWEEN 20 AND 800
    AND o.observation_datetime IS NOT NULL
),
fio2_measure AS (
  SELECT
    m.person_id,
    m.measurement_datetime AS t,
    CASE
      WHEN m.value_as_number > 1.5 AND m.value_as_number <= 100 THEN m.value_as_number / 100.0
      WHEN m.value_as_number > 100 THEN NULL
      ELSE m.value_as_number
    END AS fio2
  FROM :cdm_schema.measurement m
  JOIN :results_schema.concept_set_members fc
    ON fc.concept_id = m.measurement_concept_id
   AND fc.concept_set_name = 'fio2'
  WHERE m.value_as_number BETWEEN 0.21 AND 100
    AND m.measurement_datetime IS NOT NULL
),
fio2_observ AS (
  SELECT
    o.person_id,
    o.observation_datetime AS t,
    CASE
      WHEN o.value_as_number > 1.5 AND o.value_as_number <= 100 THEN o.value_as_number / 100.0
      ELSE o.value_as_number
    END AS fio2
  FROM :cdm_schema.observation o
  JOIN :results_schema.concept_set_members fc
    ON fc.concept_id = o.observation_concept_id
   AND fc.concept_set_name = 'fio2'
  WHERE o.value_as_number BETWEEN 0.21 AND 100
    AND o.observation_datetime IS NOT NULL
),
fio2 AS (
  SELECT * FROM fio2_measure
  UNION ALL
  SELECT * FROM fio2_observ
)
SELECT
  p.person_id,
  p.t AS pao2_datetime,
  p.pao2,
  f.t AS fio2_datetime,
  f.fio2,
  ROUND((p.pao2 / NULLIF(f.fio2, 0))::numeric, 1) AS pf_ratio,
  ABS(EXTRACT(EPOCH FROM (p.t - f.t)) / 60.0) AS minutes_apart
FROM pao2 p
JOIN fio2 f
  ON f.person_id = p.person_id
  AND ABS(EXTRACT(EPOCH FROM (p.t - f.t))) <= 3600
WHERE f.fio2 BETWEEN 0.21 AND 1.0
  AND p.pao2 / NULLIF(f.fio2,0) BETWEEN 20 AND 800;

COMMENT ON VIEW :results_schema.view_pao2_fio2_pairs IS
'PaO2/FiO2 pairs from canonical concept sets, both measurement+observation. Handles % and fraction values.';
