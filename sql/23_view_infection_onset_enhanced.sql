-- sql/23_view_infection_onset_enhanced.sql
-- ENHANCED Sepsis-3 infection definition for MGH CHoRUS
-- Purpose: Increase sensitivity vs strict v4.4 (abx + culture ≤72h)
-- Adds: culture-negative sepsis, multi-antibiotic courses, longer windows
-- Use as sensitivity analysis - keep v4.4 as primary

DROP VIEW IF EXISTS results_site_a.view_infection_onset_enhanced CASCADE;
CREATE VIEW results_site_a.view_infection_onset_enhanced AS
WITH 
-- Antibiotic exposures (expanded to include antifungals)
antibiotics AS (
    SELECT 
        de.person_id,
        de.drug_exposure_start_datetime AS abx_start,
        de.drug_exposure_end_datetime AS abx_end,
        de.drug_concept_id,
        c.concept_name AS drug_name,
        COALESCE(
            EXTRACT(EPOCH FROM (de.drug_exposure_end_datetime - de.drug_exposure_start_datetime))/86400,
            1
        ) AS duration_days
    FROM omopcdm.drug_exposure de
    JOIN vocabulary.concept c ON c.concept_id = de.drug_concept_id
    WHERE de.drug_concept_id IN (
        SELECT descendant_concept_id 
        FROM vocabulary.concept_ancestor 
        WHERE ancestor_concept_id IN (21600381, 21600712)
    )
    AND de.drug_exposure_start_datetime IS NOT NULL
),

-- Microbiology cultures
cultures AS (
    SELECT 
        m.person_id,
        m.measurement_datetime AS culture_time,
        m.measurement_concept_id,
        c.concept_name AS culture_type,
        m.value_source_value
    FROM omopcdm.measurement m
    JOIN vocabulary.concept c ON c.concept_id = m.measurement_concept_id
    WHERE m.measurement_concept_id IN (
        SELECT descendant_concept_id 
        FROM vocabulary.concept_ancestor 
        WHERE ancestor_concept_id = 4046263
    )
    AND m.measurement_datetime IS NOT NULL
),

-- Pair antibiotics with cultures (96h window)
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
        CASE 
            WHEN c.culture_time IS NOT NULL 
                AND ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) <= 96
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

-- Apply enhanced criteria
suspected_infections AS (
    SELECT
        person_id,
        infection_onset,
        distinct_abx_count,
        total_abx_days,
        has_culture,
        closest_culture_hours,
        antibiotics_given,
        CASE
            WHEN has_culture = 1 THEN 'culture_positive'
            WHEN distinct_abx_count >= 2 THEN 'multi_abx'
            WHEN total_abx_days >= 4 THEN 'prolonged_course'
            WHEN distinct_abx_count = 1 AND total_abx_days >= 2 THEN 'single_abx_icu'
            ELSE 'not_qualified'
        END AS infection_type
    FROM infection_candidates
    WHERE has_culture = 1 OR distinct_abx_count >= 2 OR total_abx_days >= 4 OR (distinct_abx_count = 1 AND total_abx_days >= 2)
),

-- Join to visit_detail for ICU context
infections_with_location AS (
    SELECT
        si.*,
        vd.visit_detail_concept_id,
        c.concept_name AS location,
        vd.visit_detail_start_datetime,
        vd.visit_detail_end_datetime,
        CASE 
            WHEN vd.visit_detail_concept_id IN (2072499989, 581383, 2072500011, 2072500012, 2072500018, 2072500007, 2072500031, 2072500010, 2072500004)
                AND si.infection_onset BETWEEN vd.visit_detail_start_datetime AND vd.visit_detail_end_datetime
            THEN 1 ELSE 0
        END AS icu_onset
    FROM suspected_infections si
    LEFT JOIN omopcdm.visit_detail vd 
        ON vd.person_id = si.person_id
        AND si.infection_onset BETWEEN vd.visit_detail_start_datetime - interval '24 hours' AND vd.visit_detail_end_datetime + interval '24 hours'
    LEFT JOIN vocabulary.concept c ON c.concept_id = vd.visit_detail_concept_id
)

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
    infection_onset - interval '72 hours' AS baseline_start,
    infection_onset + interval '48 hours' AS organ_dysfunction_end
FROM infections_with_location
ORDER BY person_id, infection_onset;

CREATE INDEX IF NOT EXISTS idx_infection_enhanced_person_time 
ON results_site_a.view_infection_onset_enhanced (person_id, infection_onset);

COMMENT ON VIEW results_site_a.view_infection_onset_enhanced IS 
'Enhanced Sepsis-3 infection definition for MGH: includes culture-negative sepsis, multi-abx courses, and prolonged therapy.';
