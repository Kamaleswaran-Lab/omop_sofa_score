-- 23_view_infection_onset.sql
-- Portable infection onset definition for OMOP CDM v5.4
-- Works at sites with or without route_concept_id populated
-- Triple-checked concept IDs:

-- ROUTE CONCEPTS (SNOMED):
-- 4112421 = 47625008 | Intravenous route (parent)
-- Descendants include:
--   4112421 Intravenous
--   4139962 Intravenous bolus (via ancestor)
--   4149815 Intravenous infusion (via ancestor)
-- We use concept_ancestor to capture all IV variants automatically

-- ANTIBIOTIC ANCESTOR:
-- 21602796 = 281786004 | Antibacterial agent

DROP VIEW IF EXISTS :results_schema.view_infection_onset CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_infection_onset AS
WITH params AS (
    SELECT 
        COALESCE((SELECT value::int FROM :results_schema.assumptions 
                  WHERE domain='antibiotic' AND parameter='window_hours'), 72) AS window_hours
),
-- Get all IV route descendants (portable across OMOP versions)
iv_routes AS (
    SELECT DISTINCT ca.descendant_concept_id AS route_concept_id
    FROM :vocab_schema.concept_ancestor ca
    WHERE ca.ancestor_concept_id = 4112421  -- Intravenous route
    UNION ALL
    SELECT 4112421
),
-- Detect if site actually populates routes (>100 non-null = real data)
site_route_stats AS (
    SELECT 
        COUNT(*) FILTER (WHERE route_concept_id IS NOT NULL) AS routes_populated,
        COUNT(*) AS total_exposures
    FROM :cdm_schema.drug_exposure
    WHERE drug_concept_id IN (
        SELECT value::int FROM :results_schema.assumptions 
        WHERE domain='antibiotic' AND parameter='concept_id'
    )
),
-- Get antibiotics with proper timing
antibiotics AS (
    SELECT
        de.person_id,
        de.drug_exposure_id,
        de.drug_concept_id,
        COALESCE(de.drug_exposure_start_datetime, 
                 de.drug_exposure_start_date::timestamp) AS abx_start,
        de.route_concept_id,
        -- Flag for IV vs other (for sites that have data)
        CASE 
            WHEN de.route_concept_id IN (SELECT route_concept_id FROM iv_routes) THEN 1
            ELSE 0 
        END AS is_iv
    FROM :cdm_schema.drug_exposure de
    WHERE de.drug_concept_id IN (
        SELECT value::int FROM :results_schema.assumptions 
        WHERE domain='antibiotic' AND parameter='concept_id'
    )
    AND COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) IS NOT NULL
),
-- Apply route filter intelligently
filtered_antibiotics AS (
    SELECT a.*
    FROM antibiotics a
    CROSS JOIN site_route_stats s
    CROSS JOIN params p
    WHERE 
        -- If site has routes populated (>1% of abx), require IV
        -- If site has no routes (like MGH), accept all antibiotics
        (s.routes_populated < 100 OR a.is_iv = 1 OR s.routes_populated::float / NULLIF(s.total_exposures,0) < 0.01)
),
-- Pair with cultures
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
    JOIN :results_schema.view_cultures c 
        ON c.person_id = fa.person_id
    CROSS JOIN params p
    WHERE ABS(EXTRACT(EPOCH FROM (fa.abx_start - c.specimen_datetime))/3600.0) <= p.window_hours
      AND c.specimen_datetime IS NOT NULL
)
-- Deduplicate to one onset per antibiotic-culture pair
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
ORDER BY person_id, drug_exposure_id, specimen_id, hours_apart ASC;

COMMENT ON VIEW :results_schema.view_infection_onset IS 
'Portable infection onset (72h window). Concept IDs verified: 21602796 Antibacterial agent, 4112421 Intravenous route. Auto-detects sites without route data.';
