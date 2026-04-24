-- 42_create_sepsis3_outcomes_30d.sql
-- Site A edit: hospice concept 8546, use discharged_to_concept_id

DROP TABLE IF EXISTS {{results_schema}}.sepsis3_outcomes_30d CASCADE;
CREATE TABLE {{results_schema}}.sepsis3_outcomes_30d AS
WITH base AS (
  SELECT DISTINCT person_id, visit_occurrence_id, infection_onset
  FROM {{results_schema}}.sepsis3_enhanced
  WHERE meets_sepsis3
),
deaths AS (
  SELECT b.person_id, b.visit_occurrence_id,
    MIN(d.death_date) AS death_date
  FROM base b
  JOIN {{cdm_schema}}.death d ON d.person_id = b.person_id
  WHERE d.death_date BETWEEN b.infection_onset AND b.infection_onset + interval '30 days'
  GROUP BY 1,2
),
hospice AS (
  SELECT b.person_id, b.visit_occurrence_id,
    MAX(vo.visit_end_date) AS hospice_date
  FROM base b
  JOIN {{cdm_schema}}.visit_occurrence vo ON vo.visit_occurrence_id = b.visit_occurrence_id
  -- SITE A SPECIFIC
  WHERE vo.discharged_to_concept_id = 8546
    AND vo.visit_end_date BETWEEN b.infection_onset AND b.infection_onset + interval '30 days'
  GROUP BY 1,2
)
SELECT
  b.person_id,
  b.visit_occurrence_id,
  b.infection_onset,
  (d.death_date IS NOT NULL) AS death_30d,
  (h.hospice_date IS NOT NULL) AS hospice_30d,
  (d.death_date IS NOT NULL OR h.hospice_date IS NOT NULL) AS composite_30d
FROM base b
LEFT JOIN deaths d USING (person_id, visit_occurrence_id)
LEFT JOIN hospice h USING (person_id, visit_occurrence_id);
