DROP VIEW IF EXISTS :results_schema.view_infection_onset CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_infection_onset AS
WITH abx AS (
  SELECT
    de.person_id,
    de.drug_exposure_id,
    COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS abx_time,
    de.visit_occurrence_id,
    de.route_concept_id
  FROM :cdm_schema.drug_exposure de
  WHERE de.drug_concept_id IN (
    SELECT value::int FROM :results_schema.assumptions WHERE domain='antibiotic'
  )
  -- MGH correct IV + common enteral routes for sepsis work
  AND de.route_concept_id IN (4171047, 4132161, 4132254, 4132711) -- IV, Oral, G-tube, NG
),
cult AS (
  SELECT person_id, specimen_id, specimen_datetime, visit_occurrence_id
  FROM :results_schema.view_cultures
)
SELECT DISTINCT ON (abx.person_id, abx.abx_time, cult.specimen_datetime)
  abx.person_id,
  abx.abx_time,
  cult.specimen_datetime AS culture_time,
  LEAST(abx.abx_time, cult.specimen_datetime) AS infection_onset_time,
  GREATEST(abx.abx_time, cult.specimen_datetime) AS infection_later_time,
  ABS(EXTRACT(EPOCH FROM (abx.abx_time - cult.specimen_datetime))/3600) AS hours_apart,
  abx.visit_occurrence_id,
  cult.specimen_id,
  abx.route_concept_id
FROM abx
JOIN cult USING (person_id)
WHERE ABS(EXTRACT(EPOCH FROM (abx.abx_time - cult.specimen_datetime))/3600) <= 72
  AND abx.abx_time IS NOT NULL
  AND cult.specimen_datetime IS NOT NULL;
