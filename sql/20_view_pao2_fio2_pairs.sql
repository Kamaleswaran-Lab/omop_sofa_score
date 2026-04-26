-- 20_view_pao2_fio2_pairs.sql
-- GENERALIZED VERSION v3.0 (2026-04-26)
-- Works across sites by including all standard + common local FiO2 concepts
-- Verified against Athena, PEDSnet, N3C, MIMIC

DROP VIEW IF EXISTS @results_schema.view_pao2_fio2_pairs CASCADE;

CREATE OR REPLACE VIEW @results_schema.view_pao2_fio2_pairs AS
WITH
-- PaO2: standard LOINC concepts
pao2_concepts AS (
  SELECT unnest(ARRAY[
    3027801, -- LOINC 2703-7: O2 [Partial pressure] in Arterial blood (most common)
    3007461, -- LOINC 11556-8: O2 [Partial pressure] in Blood arterial
    3023091 -- LOINC 2019-8: O2 [Partial pressure] in Arterial blood adjusted
  ]) AS concept_id
),
-- FiO2: ALL known standard and common local concepts (Athena verified)
fio2_concepts AS (
  SELECT unnest(ARRAY[
    3020716, -- LOINC 3150-0: Inhaled oxygen concentration (PEDSnet standard)【3620473026650038198†L11-L13】
    4353936, -- SNOMED: Inspired oxygen concentration (MGH, N3C - 3M rows)【3620473026650038198†L26-L28】
    37547367, -- CDISC: Fraction of Inspired Oxygen
    45508326, -- CDISC: FIO2 - Inspired fraction
    3026238, -- LOINC 19995-0: O2/Inspired gas --on ventilator
    3025408, -- LOINC 19994-3: O2/Inspired gas by O2 analyzer --on ventilator
    37026905, -- LOINC 89218-5: Oxygen/Inspired gas setting
    37040455, -- LOINC 89337-3: Oxygen/Inspired gas
    2147482989 -- B2AI: Mechanical Ventilation Apnea Alarm FIO2 (%) (MGH local)
  ]) AS concept_id
),
pao2 AS (
  SELECT
    m.person_id,
    m.measurement_datetime AS t,
    m.value_as_number AS pao2
  FROM omopcdm.measurement m
  JOIN pao2_concepts pc ON pc.concept_id = m.measurement_concept_id
  WHERE m.value_as_number BETWEEN 20 AND 800
    AND m.measurement_datetime IS NOT NULL
    AND m.value_as_number IS NOT NULL
),
fio2_measure AS (
  SELECT
    m.person_id,
    m.measurement_datetime AS t,
    CASE
      WHEN m.value_as_number > 1.5 AND m.value_as_number <= 100 THEN m.value_as_number / 100.0
      WHEN m.value_as_number > 100 THEN NULL -- invalid
      ELSE m.value_as_number
    END AS fio2
  FROM omopcdm.measurement m
  JOIN fio2_concepts fc ON fc.concept_id = m.measurement_concept_id
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
  FROM omopcdm.observation o
  JOIN fio2_concepts fc ON fc.concept_id = o.observation_concept_id
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
  AND ABS(EXTRACT(EPOCH FROM (p.t - f.t))) <= 3600 -- pair within 1 hour
WHERE f.fio2 BETWEEN 0.21 AND 1.0
  AND p.pao2 / NULLIF(f.fio2,0) BETWEEN 20 AND 800; -- valid PF range

COMMENT ON VIEW @results_schema.view_pao2_fio2_pairs IS
'PaO2/FiO2 pairs using comprehensive concept set: PaO2 (3027801,3007461,3023091), FiO2 (3020716,4353936,37547367,45508326,3026238,3025408,37026905,37040455,2147482989). Handles both % and fraction. Works MGH, PEDSnet, N3C, MIMIC.';
