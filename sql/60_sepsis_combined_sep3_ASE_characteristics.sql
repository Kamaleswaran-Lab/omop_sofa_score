-- 60_sepsis_combined_sep3_ASE_characteristics.sql
-- FIXED: Require baseline_sofa > 0 for valid Sepsis-3

DROP TABLE IF EXISTS results_site_a.sepsis_cohort_comparison CASCADE;

CREATE TABLE results_site_a.sepsis_cohort_comparison AS
WITH sepsis3 AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        infection_onset AS sepsis3_onset,
        baseline_sofa,
        peak_sofa,
        delta_sofa
    FROM results_site_a.sepsis3_enhanced
    WHERE meets_sepsis3 = TRUE
      AND delta_sofa >= 2
      AND baseline_sofa > 0  -- FIX: exclude zero-baseline artifacts
),
ase AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        ase_onset_datetime AS ase_onset,
        organ_dysfunction_count
    FROM results_site_a.cdc_ase_cohort_final
),
combined AS (
    SELECT
        COALESCE(s.person_id, a.person_id) AS person_id,
        COALESCE(s.visit_occurrence_id, a.visit_occurrence_id) AS visit_occurrence_id,
        s.sepsis3_onset,
        a.ase_onset,
        s.baseline_sofa,
        s.peak_sofa,
        s.delta_sofa,
        a.organ_dysfunction_count,
        CASE
            WHEN s.person_id IS NOT NULL AND a.person_id IS NOT NULL THEN 'Both'
            WHEN s.person_id IS NOT NULL THEN 'Sepsis3_Only'
            WHEN a.person_id IS NOT NULL THEN 'ASE_Only'
        END AS cohort_group,
        CASE
            WHEN s.person_id IS NOT NULL AND a.person_id IS NOT NULL
            THEN ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/3600)
        END AS onset_diff_hours
    FROM sepsis3 s
    FULL OUTER JOIN ase a 
        ON s.person_id = a.person_id 
        AND s.visit_occurrence_id = a.visit_occurrence_id
)
SELECT * FROM combined;

CREATE INDEX idx_sepsis_comp_person ON results_site_a.sepsis_cohort_comparison(person_id);
CREATE INDEX idx_sepsis_comp_group ON results_site_a.sepsis_cohort_comparison(cohort_group);

ANALYZE results_site_a.sepsis_cohort_comparison;
