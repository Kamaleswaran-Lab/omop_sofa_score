-- sql/23_view_infection_onset_enhanced.sql
-- Sepsis-3 infection onset: culture + antibiotic within configured window.

DROP VIEW IF EXISTS :results_schema.view_infection_onset CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_infection_onset AS
WITH params AS (
  SELECT COALESCE(
    (SELECT value::int FROM :results_schema.assumptions WHERE domain='antibiotic' AND parameter='window_hours'),
    72
  ) AS window_hours
),
-- Standard vocabulary IV routes (concept_ancestor of 4112421 = Intravenous)
vocab_iv_routes AS (
  SELECT DISTINCT ca.descendant_concept_id AS route_concept_id
  FROM :vocab_schema.concept_ancestor ca
  WHERE ca.ancestor_concept_id = 4112421  -- Intravenous route
  UNION ALL SELECT 4112421
),
-- Site-specific fallback: top routes used for antibiotics at this site
site_top_routes AS (
  SELECT route_concept_id
  FROM (
    SELECT 
      de.route_concept_id,
      COUNT(*) AS use_count,
      ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC) AS rn
    FROM :results_schema.view_antibiotics de
    WHERE de.route_concept_id IS NOT NULL
    GROUP BY de.route_concept_id
  ) ranked
  WHERE rn <= 15  -- capture IV, oral, IM, etc.
),
-- Combine: prefer vocabulary, fallback to site data if vocab empty
effective_routes AS (
  SELECT route_concept_id FROM vocab_iv_routes
  UNION
  SELECT route_concept_id FROM site_top_routes
  WHERE NOT EXISTS (SELECT 1 FROM vocab_iv_routes)
  -- Always include common systemic routes as safety net
  UNION ALL SELECT * FROM (VALUES (4171047),(4132161),(4132254),(4132711),(4302612)) AS t(route_concept_id)
),
-- Site route completeness check
site_route_stats AS (
  SELECT 
    COUNT(*) FILTER (WHERE route_concept_id IS NOT NULL) AS routes_populated,
    COUNT(*) AS total_exposures
  FROM :results_schema.view_antibiotics
),
-- All antibiotic exposures
antibiotics AS (
  SELECT
    de.person_id,
    de.drug_exposure_id,
    de.visit_occurrence_id,
    de.drug_exposure_start_datetime AS abx_start,
    de.route_concept_id,
    CASE 
      WHEN de.route_concept_id IN (SELECT route_concept_id FROM effective_routes) THEN 1 
      ELSE 0 
    END AS is_iv_systemic
  FROM :results_schema.view_antibiotics de
),
-- Filter based on site data quality
filtered_antibiotics AS (
  SELECT a.*
  FROM antibiotics a
  CROSS JOIN site_route_stats s
  CROSS JOIN params p
  WHERE 
    -- If routes are mostly missing (<100 or <1%), keep all (Sepsis-3 allows)
    s.routes_populated < 100 
    OR (s.routes_populated::float / NULLIF(s.total_exposures,0) < 0.01)
    -- Otherwise keep only systemic routes
    OR a.is_iv_systemic = 1
    OR a.route_concept_id IS NULL
),
-- Pair with cultures
paired AS (
  SELECT
    fa.person_id,
    fa.drug_exposure_id,
    fa.visit_occurrence_id,
    c.specimen_id,
    fa.abx_start,
    c.specimen_datetime AS culture_time,
    LEAST(fa.abx_start, c.specimen_datetime) AS infection_onset,
    ABS(EXTRACT(EPOCH FROM (fa.abx_start - c.specimen_datetime))/3600.0) AS hours_apart,
    fa.is_iv_systemic AS is_iv,
    fa.route_concept_id
  FROM filtered_antibiotics fa
  JOIN :results_schema.view_cultures c 
    ON c.person_id = fa.person_id
  CROSS JOIN params p
  WHERE c.specimen_datetime IS NOT NULL
    AND (
      -- Culture first, antibiotic within 72h (using the parameter)
      (c.specimen_datetime <= fa.abx_start AND EXTRACT(EPOCH FROM (fa.abx_start - c.specimen_datetime))/3600.0 <= p.window_hours)
      OR
      -- Antibiotic first, culture within 24h (strict Sepsis-3 limit)
      (fa.abx_start < c.specimen_datetime AND EXTRACT(EPOCH FROM (c.specimen_datetime - fa.abx_start))/3600.0 <= 24)
    )
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
  route_concept_id,
  visit_occurrence_id
FROM paired
ORDER BY person_id, drug_exposure_id, specimen_id, hours_apart;

COMMENT ON VIEW :results_schema.view_infection_onset IS 
'Sepsis-3 infection onset pairs (Culture first: abx <=72h. Abx first: culture <=24h). Generalizable: auto-detects IV routes.';
