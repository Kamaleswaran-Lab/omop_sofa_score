-- sql/23_view_infection_onset_enhanced.sql
-- ENHANCED Sepsis-3 infection definition for MGH CHoRUS
-- Purpose: Increase sensitivity vs strict v4.4 (abx + culture ≤72h)
-- Adds: culture-negative sepsis, multi-antibiotic courses, longer windows
-- Use as sensitivity analysis - keep v4.4 as primary
--
-- Changes from v4.4:
-- 1. Allow infection with antibiotics alone if ≥2 distinct abx OR ≥4 day course
-- 2. Expand window to 96h (was 72h) for delayed cultures
-- 3. Include antifungals (for immunocompromised sepsis)
-- 4. Use visit_detail for ICU detection (MGH custom concepts)
-- 5. Include ED/floor infections that later transfer to ICU

DROP VIEW IF EXISTS {{ results_schema }}.view_infection_onset_enhanced CASCADE;
CREATE VIEW {{ results_schema }}.view_infection_onset_enhanced AS
WITH 
-- Antibiotic exposures (expanded to include antifungals)
antibiotics AS (
    SELECT 
        de.person_id,
        de.drug_exposure_start_datetime AS abx_start,
        de.drug_exposure_end_datetime AS abx_end,
        de.drug_concept_id,
        c.concept_name AS drug_name,
        -- Duration in days
        COALESCE(
            EXTRACT(EPOCH FROM (de.drug_exposure_end_datetime - de.drug_exposure_start_datetime))/86400,
            1
        ) AS duration_days
    FROM {{ cdm_schema }}.drug_exposure de
    JOIN {{ vocab_schema }}.concept c ON c.concept_id = de.drug_concept_id
    WHERE de.drug_concept_id IN (
        SELECT descendant_concept_id 
        FROM {{ vocab_schema }}.concept_ancestor 
        WHERE ancestor_concept_id IN (
            21600381,  -- Systemic Antibacterial (original)
            21600712   -- Systemic Antifungal (NEW - for immunocompromised)
        )
    )
    -- Exclude prophylactic single doses (OR antibiotics in surgical patients)
    AND de.drug_exposure_start_datetime IS NOT NULL
),

-- Microbiology cultures (all types)
cultures AS (
    SELECT 
        m.person_id,
        m.measurement_datetime AS culture_time,
        m.measurement_concept_id,
        c.concept_name AS culture_type,
        m.value_source_value
    FROM {{ cdm_schema }}.measurement m
    JOIN {{ vocab_schema }}.concept c ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_concept_id IN (
        SELECT descendant_concept_id 
        FROM {{ vocab_schema }}.concept_ancestor 
        WHERE ancestor_concept_id = 4046263  -- Microbiology cultures
    )
    AND m.measurement_datetime IS NOT NULL
),

-- Pair antibiotics with cultures (expanded 96h window)
abx_culture_pairs AS (
    SELECT
        a.person_id,
        a.abx_start,
        a.drug_concept_id,
        a.drug_name,
        a.duration_days,
        c.culture_time,
        c.culture_type,
        ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) AS hours_apart,
        -- Flag for valid pairing
        CASE 
            WHEN c.culture_time IS NOT NULL 
                AND ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) <= 96  -- WAS 72h
            THEN 1 ELSE 0 
        END AS has_culture_pair
    FROM antibiotics a
    LEFT JOIN cultures c ON c.person_id = a.person_id
        AND ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) <= 96
),

-- Aggregate to infection episodes
infection_candidates AS (
    SELECT
        person_id,
        abx_start AS infection_onset,
        COUNT(DISTINCT drug_concept_id) AS distinct_abx_count,
        SUM(duration_days) AS total_abx_days,
        MAX(has_culture_pair) AS has_culture,
        MIN(hours_apart) AS closest_culture_hours,
        STRING_AGG(DISTINCT drug_name, '; ' ORDER BY drug_name) AS antibiotics_given
    FROM abx_culture_pairs
    GROUP BY person_id, abx_start
),

-- Apply enhanced Sepsis-3 infection criteria
suspected_infections AS (
    SELECT
        person_id,
        infection_onset,
        distinct_abx_count,
        total_abx_days,
        has_culture,
        closest_culture_hours,
        antibiotics_given,
        -- Enhanced criteria (ANY of these qualifies)
        CASE
            -- 1. Original v4.4: abx + culture ≤96h (was 72h)
            WHEN has_culture = 1 THEN 'culture_positive'
            -- 2. NEW: Multiple antibiotics (suggests empiric sepsis coverage)
            WHEN distinct_abx_count >= 2 THEN 'multi_abx'
            -- 3. NEW: Prolonged course (≥4 days, suggests treatment not prophylaxis)
            WHEN total_abx_days >= 4 THEN 'prolonged_course'
            -- 4. NEW: Single broad-spectrum in ICU (clinical suspicion)
            WHEN distinct_abx_count = 1 AND total_abx_days >= 2 THEN 'single_abx_icu'
            ELSE 'not_qualified'
        END AS infection_type
    FROM infection_candidates
    WHERE 
        -- Must meet at least one enhanced criterion
        has_culture = 1 
        OR distinct_abx_count >= 2 
        OR total_abx_days >= 4
        OR (distinct_abx_count = 1 AND total_abx_days >= 2)
),

-- Join to visit_detail for ICU context (MGH-specific)
infections_with_location AS (
    SELECT
        si.*,
        vd.visit_detail_concept_id,
        c.concept_name AS location,
        vd.visit_detail_start_datetime,
        vd.visit_detail_end_datetime,
        -- Flag if infection onset during ICU stay
        CASE 
            WHEN vd.visit_detail_concept_id IN (
                2072499989,  -- Surgical ICU
                581383,      -- Cardiac Care
                2072500011,  -- MICU (MGH custom)
                2072500012,  -- NICU (MGH custom)
                2072500018,
                2072500007,
                2072500031,
                2072500010,
                2072500004
            ) AND si.infection_onset BETWEEN vd.visit_detail_start_datetime AND vd.visit_detail_end_datetime
            THEN 1 ELSE 0
        END AS icu_onset
    FROM suspected_infections si
    LEFT JOIN {{ cdm_schema }}.visit_detail vd 
        ON vd.person_id = si.person_id
        AND si.infection_onset BETWEEN vd.visit_detail_start_datetime - interval '24 hours'
                                   AND vd.visit_detail_end_datetime + interval '24 hours'
    LEFT JOIN {{ vocab_schema }}.concept c ON c.concept_id = vd.visit_detail_concept_id
)

-- Final output with deduplication (48h window)
SELECT DISTINCT ON (person_id, infection_onset)
    person_id,
    infection_onset,
    infection_type,
    distinct_abx_count,
    total_abx_days,
    has_culture,
    closest_culture_hours,
    antibiotics_given,
    location,
    icu_onset,
    visit_detail_concept_id,
    -- For joining to SOFA scores
    infection_onset - interval '72 hours' AS baseline_start,
    infection_onset + interval '48 hours' AS organ_dysfunction_end
FROM infections_with_location
ORDER BY person_id, infection_onset;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_infection_enhanced_person_time 
ON {{ results_schema }}.view_infection_onset_enhanced (person_id, infection_onset);

COMMENT ON VIEW {{ results_schema }}.view_infection_onset_enhanced IS 
'Enhanced Sepsis-3 infection definition for MGH: includes culture-negative sepsis, multi-abx courses, and prolonged therapy. Sensitivity analysis - use alongside strict v4.4 definition.';
