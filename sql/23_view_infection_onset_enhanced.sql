-- 23_view_infection_onset_enhanced.sql
-- Site A edit: add culture_site for source breakdown
-- v4.5 enhanced pragmatic infection definition

DROP VIEW IF EXISTS {{results_schema}}.view_infection_onset_enhanced CASCADE;
CREATE OR REPLACE VIEW {{results_schema}}.view_infection_onset_enhanced AS
WITH abx AS (
  SELECT person_id, visit_occurrence_id, drug_exposure_start_datetime AS antibiotic_start,
         drug_concept_id, ROW_NUMBER() OVER (PARTITION BY person_id, visit_occurrence_id ORDER BY drug_exposure_start_datetime) AS rn
  FROM {{cdm_schema}}.drug_exposure de
  JOIN {{cdm_schema}}.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
  WHERE ca.ancestor_concept_id = 21602796 -- systemic antibiotics
),
cult AS (
  SELECT m.person_id, m.visit_occurrence_id, m.measurement_datetime AS culture_start,
         m.specimen_source_concept_id,
         cs.concept_name AS culture_site,
         m.measurement_concept_id
  FROM {{cdm_schema}}.measurement m
  LEFT JOIN {{vocab_schema}}.concept cs ON cs.concept_id = m.specimen_source_concept_id
  WHERE m.measurement_concept_id IN (SELECT concept_id FROM {{vocab_schema}}.concept WHERE concept_class_id = 'Microbiology')
),
paired AS (
  SELECT
    COALESCE(a.person_id, c.person_id) AS person_id,
    COALESCE(a.visit_occurrence_id, c.visit_occurrence_id) AS visit_occurrence_id,
    LEAST(a.antibiotic_start, c.culture_start) AS infection_onset,
    a.antibiotic_start,
    c.culture_start,
    c.culture_site,
    CASE
      WHEN c.culture_start <= a.antibiotic_start THEN 'culture_first'
      WHEN a.antibiotic_start < c.culture_start THEN 'antibiotic_first'
      ELSE 'unknown'
    END AS infection_type,
    ABS(EXTRACT(EPOCH FROM (a.antibiotic_start - c.culture_start))/3600.0) AS hrs_diff
  FROM abx a
  FULL OUTER JOIN cult c
    ON a.person_id = c.person_id
   AND a.visit_occurrence_id = c.visit_occurrence_id
   AND ABS(EXTRACT(EPOCH FROM (a.antibiotic_start - c.culture_start))/3600) <= 96 -- Site A: 96h window
  WHERE a.antibiotic_start IS NOT NULL OR c.culture_start IS NOT NULL
)
SELECT DISTINCT ON (person_id, visit_occurrence_id, infection_onset)
  person_id,
  visit_occurrence_id,
  infection_onset,
  infection_type,
  antibiotic_start,
  culture_start,
  culture_site,
  hrs_diff
FROM paired
WHERE infection_onset < CURRENT_DATE -- exclude future test data
ORDER BY person_id, visit_occurrence_id, infection_onset, hrs_diff;
