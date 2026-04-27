-- sql/23_view_infection_onset.sql
DROP VIEW IF EXISTS :results_schema.view_infection_onset CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_infection_onset AS
WITH params AS (
  SELECT COALESCE(
    (SELECT value::int FROM :results_schema.assumptions WHERE domain='antibiotic' AND parameter='window_hours'),
    72
  ) AS window_hours
),
-- 1. Standard IV routes from vocabulary
vocab_iv AS (
  SELECT DISTINCT ca.descendant_concept_id AS route_concept_id
  FROM :vocab_schema.concept_ancestor ca
  WHERE ca.ancestor_concept_id = 4112421  -- Intravenous route
  UNION ALL SELECT 4112421
),
-- 2. Site-specific top routes for antibiotics (fallback)
site_top_routes AS (
  SELECT route_concept_id
  FROM (
    SELECT de.route_concept_id, COUNT(*) AS cnt,
           ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
    FROM :cdm_schema.drug_exposure de
    WHERE de.drug_concept_id IN (
      SELECT value::int FROM :results_schema.assumptions WHERE domain='antibiotic' AND parameter='concept_id'
    )
    AND de.route_concept_id IS NOT NULL
    GROUP BY 1
  ) t
  WHERE rn <= 10  -- top 10 routes at this site
),
-- 3. Combine: use vocab if it has data, else use site top routes
iv_routes AS (
  SELECT route_concept_id FROM vocab_iv
  UNION
  SELECT route_concept_id FROM site_top_routes
  WHERE NOT EXISTS (SELECT 1 FROM vocab_iv)
),
-- 4. Site stats to decide filtering
site_stats AS (
  SELECT 
    COUNT(*) FILTER (WHERE route_concept_id IS NOT NULL) AS routes_populated,
    COUNT(*) AS total
  FROM :cdm_schema.drug_exposure
  WHERE drug_concept_id IN (
    SELECT value::int FROM :results_schema.assumptions WHERE domain='antibiotic' AND parameter='concept_id'
  )
),
antibiotics AS (
  SELECT
    de.person_id,
    de.drug_exposure_id,
    COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS abx_start,
    de.route_concept_id,
    CASE WHEN de.route_concept_id IN (SELECT route_concept_id FROM iv_routes) THEN 1 ELSE 0 END AS is_iv
  FROM :cdm_schema.drug_exposure de
  WHERE de.drug_concept_id IN (
    SELECT value::int FROM :results_schema.assumptions WHERE domain='antibiotic' AND parameter='concept_id'
  )
  AND COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) IS NOT NULL
),
filtered_antibiotics AS (
  SELECT a.*
  FROM antibiotics a
  CROSS JOIN site_stats s
  -- Keep all if routes are sparse (<1% populated), otherwise keep only IV/systemic
  WHERE s.routes_populated < 100
     OR (s.routes_populated::float / NULLIF(s.total,0) < 0.01)
     OR a.is_iv = 1
     OR a.route_concept_id IS NULL
),
paired AS (
  SELECT
    fa.person_id,
    fa.drug_exposure_id,
    c.specimen_id,
    fa.abx_start,
    c.specimen_datetime AS culture_time,
    LEAST(fa.abx_start, c.specimen_datetime) AS infection_onset,
    ABS(EXTRACT(EPOCH FROM (fa.abx_start - c.specimen_datetime))/3600.0) AS hours_apart,
    fa.is_iv,
    fa.route_concept_id
  FROM filtered_antibiotics fa
  JOIN :results_schema.view_cultures c USING (person_id)
  CROSS JOIN params p
  WHERE c.specimen_datetime IS NOT NULL
    AND ABS(EXTRACT(EPOCH FROM (fa.abx_start - c.specimen_datetime))/3600.0) <= p.window_hours
)
SELECT DISTINCT ON (person_id, drug_exposure_id, specimen_id)
  person_id,
  infection_onset,
  abx_start AS antibiotic_time,
  culture_time,
  hours_apart,
  drug_exposure_id,
  specimen_id,
  is_iv,
  route_concept_id
FROM paired
ORDER BY person_id, drug_exposure_id, specimen_id, hours_apart;
