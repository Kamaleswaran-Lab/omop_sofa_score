-- Standard infection onset (72h window)
DROP VIEW IF EXISTS results_site_a.view_infection_onset CASCADE;

CREATE OR REPLACE VIEW results_site_a.view_infection_onset AS
WITH abx AS (
  SELECT person_id, visit_occurrence_id,
         COALESCE(drug_exposure_start_datetime, drug_exposure_start_date::timestamp) AS abx_start
  FROM omopcdm.drug_exposure de
  JOIN results_site_a.assumptions a ON a.domain='antibiotic' AND a.concept_id = de.drug_concept_id
  WHERE de.route_concept_id = 4112421  -- intravenous
),
cult AS (
  SELECT person_id, visit_occurrence_id,
         COALESCE(measurement_datetime, measurement_date::timestamp) AS culture_time
  FROM results_site_a.view_cultures
),
paired AS (
  SELECT a.person_id, a.visit_occurrence_id,
         LEAST(a.abx_start, c.culture_time) AS infection_onset,
         a.abx_start AS antibiotic_start,
         c.culture_time AS culture_start
  FROM abx a
  JOIN cult c USING (person_id, visit_occurrence_id)
  WHERE ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) <= 72
)
SELECT DISTINCT ON (person_id, visit_occurrence_id)
  person_id, visit_occurrence_id, infection_onset, antibiotic_start, culture_start
FROM paired
ORDER BY person_id, visit_occurrence_id, infection_onset;
