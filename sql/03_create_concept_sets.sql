-- 03_create_concept_sets.sql
-- Canonical concept sets and vocabulary validation for the OMOP SOFA pipeline.

DROP TABLE IF EXISTS :results_schema.concept_set_members CASCADE;

CREATE TABLE :results_schema.concept_set_members (
  concept_set_name text NOT NULL,
  concept_id bigint NOT NULL,
  expected_domain_id text,
  require_standard boolean NOT NULL DEFAULT true,
  local_allowed boolean NOT NULL DEFAULT false,
  source text NOT NULL,
  note text,
  PRIMARY KEY (concept_set_name, concept_id)
);

-- Lab, vital, respiratory, neurologic, renal replacement, ventilation, and
-- vasopressor seed concepts. Local concepts must be explicitly marked.
INSERT INTO :results_schema.concept_set_members
  (concept_set_name, concept_id, expected_domain_id, require_standard, local_allowed, source, note)
VALUES
  -- Labs
  ('platelets', 3024929, 'Measurement', true, false, 'ATHENA', 'Platelets [#/volume] in Blood by Automated count'),
  ('platelets', 3016682, 'Measurement', true, false, 'ATHENA', 'Platelets in Plasma'),
  ('lactate', 3047181, 'Measurement', true, false, 'ATHENA', 'Lactate [Moles/volume] in Blood'),
  ('lactate', 3014111, 'Measurement', true, false, 'ATHENA', 'Lactate in Serum or Plasma'),
  ('lactate', 3008037, 'Measurement', true, false, 'ATHENA', 'Lactate in Venous blood'),
  ('bilirubin', 3013682, 'Measurement', true, false, 'ATHENA', 'Bilirubin'),
  ('bilirubin', 3024128, 'Measurement', true, false, 'ATHENA', 'Bilirubin.total'),
  ('creatinine', 3016723, 'Measurement', true, false, 'ATHENA', 'Creatinine'),
  ('urine_output', 3014315, 'Measurement', true, false, 'ATHENA', 'Urine output volume'),

  -- Vitals and neuro
  ('map', 4108290, 'Measurement', true, false, 'ATHENA', 'Invasive mean arterial pressure'),
  ('map', 3027597, 'Measurement', true, false, 'ATHENA', 'Mean arterial pressure'),
  ('map', 3019962, 'Measurement', true, false, 'ATHENA', 'MAP legacy'),
  ('sbp', 3034703, 'Measurement', true, false, 'ATHENA', 'Systolic blood pressure'),
  ('dbp', 3027598, 'Measurement', true, false, 'ATHENA', 'Diastolic blood pressure'),
  ('heart_rate', 3027018, 'Measurement', true, false, 'ATHENA', 'Heart rate'),
  ('gcs', 4093836, NULL, true, false, 'ATHENA', 'Glasgow coma score total'),
  ('gcs', 3016335, NULL, true, false, 'ATHENA', 'GCS eye'),
  ('gcs', 3009094, NULL, true, false, 'ATHENA', 'GCS verbal'),
  ('gcs', 3008223, NULL, true, false, 'ATHENA', 'GCS motor'),

  -- PaO2 and FiO2
  ('pao2', 3027801, NULL, true, false, 'ATHENA', 'O2 partial pressure arterial blood'),
  ('pao2', 3007461, NULL, true, false, 'ATHENA', 'O2 partial pressure blood arterial'),
  ('pao2', 3023091, NULL, true, false, 'ATHENA', 'O2 partial pressure adjusted arterial'),
  ('pao2', 3031717, NULL, true, false, 'ATHENA', 'Calculated arterial oxygen pressure'),
  ('pao2', 40772940, NULL, true, false, 'ATHENA', 'Arterial oxygen tension'),
  ('fio2', 3020716, NULL, true, false, 'ATHENA', 'Inhaled oxygen concentration'),
  ('fio2', 4353936, NULL, true, false, 'ATHENA', 'Inspired oxygen concentration'),
  ('fio2', 3004249, NULL, true, false, 'ATHENA', 'Inspired O2 fraction'),
  ('fio2', 3036277, NULL, true, false, 'ATHENA', 'FiO2'),
  ('fio2', 37547367, NULL, true, false, 'ATHENA', 'Fraction of Inspired Oxygen'),
  ('fio2', 45508326, NULL, true, false, 'ATHENA', 'FIO2 - Inspired fraction'),
  ('fio2', 3026238, NULL, true, false, 'ATHENA', 'O2/Inspired gas on ventilator'),
  ('fio2', 3025408, NULL, true, false, 'ATHENA', 'O2/Inspired gas by analyzer on ventilator'),
  ('fio2', 37026905, NULL, true, false, 'ATHENA', 'Oxygen/Inspired gas setting'),
  ('fio2', 37040455, NULL, true, false, 'ATHENA', 'Oxygen/Inspired gas'),
  ('fio2', 2147482989, NULL, false, true, 'LOCAL', 'Site-local FiO2 concept'),

  -- Support therapies
  ('ventilation', 4202832, 'Procedure', true, false, 'ATHENA', 'Intubation'),
  ('ventilation', 42738694, 'Procedure', true, false, 'ATHENA', 'Mechanical ventilation procedure'),
  ('ventilation', 4145896, 'Procedure', true, false, 'ATHENA', 'Ventilation support'),
  ('rrt', 4197217, 'Procedure', true, false, 'ATHENA', 'Dialysis procedure'),
  ('rrt', 2109463, 'Procedure', true, false, 'ATHENA', 'Renal replacement therapy'),
  ('vasopressor', 4328749, 'Drug', true, false, 'ATHENA', 'Norepinephrine'),
  ('vasopressor', 1338005, 'Drug', true, false, 'ATHENA', 'Epinephrine'),
  ('vasopressor', 1360635, 'Drug', true, false, 'ATHENA', 'Vasopressin'),
  ('vasopressor', 1135766, 'Drug', true, false, 'ATHENA', 'Phenylephrine'),
  ('vasopressor', 1319998, 'Drug', true, false, 'ATHENA', 'Dopamine'),
  ('vasopressor', 1337720, 'Drug', true, false, 'ATHENA', 'Dobutamine');

INSERT INTO :results_schema.concept_set_members
  (concept_set_name, concept_id, expected_domain_id, require_standard, local_allowed, source, note)
SELECT 'culture_measurement', concept_id, 'Measurement', true, false, 'ATHENA', 'Culture measurement'
FROM (VALUES
  (3023368),(3013867),(3026008),(3025099),(3039355),(40762243),
  (3003714),(3000494),(3005702),(3025941),(3011298),(3016727),
  (3027005),(3016114),(3016914),(3015479),(3045330),(40765191),
  (3037692),(3023419),(3033740),(3010254),(3019902),(3004840),
  (3017611),(3023601),(3023207),(3024461),(3015409),(3036000),
  (43533857),(3025468),(3012568),(3005988)
) AS t(concept_id)
UNION ALL
SELECT 'culture_specimen', concept_id, 'Specimen', true, false, 'ATHENA', 'Culture specimen'
FROM (VALUES
  (618898),(1447635),(3516065),(3667301),(3667306)
) AS t(concept_id);

-- Antibiotics are expanded from ATC J01 / antibacterials for systemic use.
INSERT INTO :results_schema.concept_set_members
  (concept_set_name, concept_id, expected_domain_id, require_standard, local_allowed, source, note)
SELECT DISTINCT
  'antibiotic',
  ca.descendant_concept_id,
  'Drug',
  true,
  false,
  'ATHENA concept_ancestor 21602796',
  c.concept_name
FROM :vocab_schema.concept_ancestor ca
JOIN :vocab_schema.concept c ON c.concept_id = ca.descendant_concept_id
WHERE ca.ancestor_concept_id = 21602796
  AND c.domain_id = 'Drug'
  AND c.standard_concept = 'S'
  AND c.invalid_reason IS NULL;

DROP TABLE IF EXISTS :results_schema.vasopressor_nee_factors CASCADE;
CREATE TABLE :results_schema.vasopressor_nee_factors (
  concept_id bigint PRIMARY KEY,
  vasopressor_name text NOT NULL,
  nee_factor numeric NOT NULL
);

INSERT INTO :results_schema.vasopressor_nee_factors
  (concept_id, vasopressor_name, nee_factor)
VALUES
  (4328749, 'norepinephrine', 1.0),
  (1338005, 'epinephrine', 1.0),
  (1360635, 'vasopressin', 2.5),
  (1135766, 'phenylephrine', 0.1),
  (1319998, 'dopamine', 0.01),
  (1337720, 'dobutamine', 0.01);

DROP TABLE IF EXISTS :results_schema.concept_set_validation_failures CASCADE;
CREATE TABLE :results_schema.concept_set_validation_failures AS
SELECT
  m.concept_set_name,
  m.concept_id,
  m.source,
  m.expected_domain_id,
  c.domain_id AS actual_domain_id,
  c.standard_concept,
  c.invalid_reason,
  CASE
    WHEN c.concept_id IS NULL AND NOT m.local_allowed THEN 'missing_from_vocabulary'
    WHEN c.invalid_reason IS NOT NULL THEN 'invalid_concept'
    WHEN m.expected_domain_id IS NOT NULL AND c.domain_id <> m.expected_domain_id THEN 'wrong_domain'
    WHEN m.require_standard AND COALESCE(c.standard_concept, '') <> 'S' THEN 'non_standard'
  END AS failure_reason
FROM :results_schema.concept_set_members m
LEFT JOIN :vocab_schema.concept c ON c.concept_id = m.concept_id
WHERE
  (c.concept_id IS NULL AND NOT m.local_allowed)
  OR c.invalid_reason IS NOT NULL
  OR (m.expected_domain_id IS NOT NULL AND c.domain_id <> m.expected_domain_id)
  OR (m.require_standard AND COALESCE(c.standard_concept, '') <> 'S');

SELECT COUNT(*) AS concept_set_validation_failure_count
FROM :results_schema.concept_set_validation_failures
\gset

\if :concept_set_validation_failure_count
  \echo 'Concept set validation failed. Inspect :results_schema.concept_set_validation_failures.'
  \quit 3
\endif

CREATE INDEX idx_concept_set_members_name_id
  ON :results_schema.concept_set_members(concept_set_name, concept_id);
