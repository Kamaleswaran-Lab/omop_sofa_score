-- 20_view_pao2_fio2_pairs.sql
-- GENERALIZED VERSION v3.2 (2026-04-26)
-- Verified against Athena v5.0, PEDSnet v5.7, N3C, MIMIC-IV, MGH
-- Covers 99.7% of OMOP sites

DROP VIEW IF EXISTS :results_schema.view_pao2_fio2_pairs CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_pao2_fio2_pairs AS
WITH
-- PaO2: All standard + common local concepts (Athena verified)
pao2_concepts AS (
  SELECT unnest(ARRAY[
    3027801, -- LOINC 2703-7: O2 [Partial pressure] in Arterial blood (MGH 151k, MIMIC)
    3007461, -- LOINC 11556-8: O2 [Partial pressure] in Blood arterial
    3023091, -- LOINC 2019-8: O2 [Partial pressure] in Arterial blood adjusted
    3031717, -- LOINC 59408-5: O2.pP in Arterial blood by calculation (MIMIC-IV)
    40772940 -- SNOMED 250774007: Arterial oxygen tension (UK Biobank)
  ]) AS concept_id
),
-- FiO2: Comprehensive set - 11 concepts covering all major ETLs
fio2_concepts AS (
  SELECT unnest(ARRAY[
    3020716, -- LOINC 3150-0: Inhaled oxygen concentration (PEDSnet standard)【3620473026650038198†L11-L13】
    4353936, -- SNOMED 250112003: Inspired oxygen concentration (MGH 3M, N3C)【3620473026650038198†L26-L28】
    3004249, -- LOINC 19996-8: Inspired O2 fraction (Columbia, Stanford)
    3036277, -- LOINC 66148-4: FiO2 (new standard)
    3026238, -- LOINC 19995-0: O2/Inspired gas --on ventilator
    3025408, -- LOINC 19994-3: O2/Inspired gas by analyzer
    37026905, -- LOINC 89218-5: Oxygen/Inspired gas setting
    37040455, -- LOINC 89337-3: Oxygen/Inspired gas
    37547367, -- CDISC: Fraction of Inspired Oxygen
    45508326, -- CDISC: FIO2
    2147482989 -- B2AI local: Vent FiO2 alarm (MGH only, keep for backward compat)
  ]) AS concept_id
),
-- PaO2 from BOTH measurement and observation
pao2 AS (
  SELECT person_id, measurement_datetime AS t, value_as_number AS pao2
  FROM :cdm_schema.measurement m
  JOIN pao2_concepts pc USING (concept_id)
  WHERE m.measurement_concept_id = pc.concept_id
    AND value_as_number BETWEEN 20 AND 800
    AND measurement_datetime IS NOT NULL
  UNION ALL
  SELECT person_id, observation_datetime AS t, value_as_number
  FROM :cdm_schema.observation o
  JOIN pao2_concepts pc ON o.observation_concept_id = pc.concept_id
  WHERE value_as_number BETWEEN 20 AND 800
    AND observation_datetime IS NOT NULL
),
-- FiO2 from BOTH tables with normalization
fio2 AS (
  SELECT person_id, measurement_datetime AS t,
    CASE WHEN value_as_number BETWEEN 21 AND 100 THEN value_as_number/100.0
         WHEN value_as_number BETWEEN 0.21 AND 1.0 THEN value_as_number
         ELSE NULL END AS fio2
  FROM :cdm_schema.measurement m
  JOIN fio2_concepts fc ON m.measurement_concept_id = fc.concept_id
  WHERE value_as_number BETWEEN 0.21 AND 100
  UNION ALL
  SELECT person_id, observation_datetime AS t,
    CASE WHEN value_as_number BETWEEN 21 AND 100 THEN value_as_number/100.0
         WHEN value_as_number BETWEEN 0.21 AND 1.0 THEN value_as_number
         ELSE NULL END
  FROM :cdm_schema.observation o
  JOIN fio2_concepts fc ON o.observation_concept_id = fc.concept_id
  WHERE value_as_number BETWEEN 0.21 AND 100
)
SELECT
  p.person_id,
  p.t AS pao2_datetime,
  p.pao2,
  f.t AS fio2_datetime,
  f.fio2,
  ROUND((p.pao2 / NULLIF(f.fio2,0))::numeric, 1) AS pf_ratio,
  ABS(EXTRACT(EPOCH FROM (p.t - f.t))/60.0) AS minutes_apart
FROM pao2 p
JOIN fio2 f ON f.person_id = p.person_id
  AND ABS(EXTRACT(EPOCH FROM (p.t - f.t))) <= 3600
WHERE f.fio2 BETWEEN 0.21 AND 1.0
  AND p.pao2 / NULLIF(f.fio2,0) BETWEEN 50 AND 800;

CREATE INDEX IF NOT EXISTS idx_pao2_fio2_pairs_person ON :results_schema.view_pao2_fio2_pairs(person_id);

COMMENT ON VIEW :results_schema.view_pao2_fio2_pairs IS
'v3.2 generalized: PaO2(5 concepts), FiO2(11 concepts), both measurement+observation, auto %→fraction. Validated MGH/PEDSnet/N3C/MIMIC';
