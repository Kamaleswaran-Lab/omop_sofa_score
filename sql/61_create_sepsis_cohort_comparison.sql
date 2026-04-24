-- rebuild_sepsis_cohort.sql
-- MGH Site A: Sepsis-3 vs CDC ASE comparison with temporal matching

DROP TABLE IF EXISTS results_site_a.sepsis_cohort_comparison CASCADE;

CREATE TABLE results_site_a.sepsis_cohort_comparison (
    person_id bigint,
    sepsis3_visit_id bigint,
    ase_visit_id bigint,
    sepsis3_onset timestamp without time zone,
    ase_onset timestamp without time zone,
    infection_type text,
    baseline_sofa integer,
    peak_sofa integer,
    delta_sofa integer,
    max_sofa_72h integer,
    sofa_severity text,
    vasopressor_72h boolean,
    ventilation_72h boolean,
    onset_type text,
    died_in_hospital integer,
    died_30d integer,
    hospital_los_days numeric,
    cohort_type text,
    onset_diff_hours numeric
);

INSERT INTO results_site_a.sepsis_cohort_comparison
WITH 
-- Sepsis-3 cohort
s AS (
    SELECT 
        person_id, 
        visit_occurrence_id, 
        infection_onset AS s_onset,
        infection_type, 
        baseline_sofa, 
        peak_sofa, 
        delta_sofa
    FROM results_site_a.sepsis3_enhanced
    WHERE meets_sepsis3 
      AND delta_sofa >= 2 
      AND baseline_sofa >= 0
),
-- CDC ASE cohort
a AS (
    SELECT 
        person_id, 
        visit_occurrence_id, 
        infection_onset AS a_onset,
        max_sofa_72h, 
        sofa_severity, 
        vasopressor_72h::boolean AS vaso, 
        ventilation_72h::boolean AS vent,
        onset_type, 
        died_in_hospital, 
        died_30d, 
        hospital_los_days
    FROM results_site_a.cdc_ase_cohort_final
),
-- All candidate pairs within 72 hours
candidates AS (
    SELECT 
        s.person_id, 
        s.visit_occurrence_id AS sv, 
        a.visit_occurrence_id AS av,
        s.s_onset, 
        a.a_onset, 
        s.infection_type,
        s.baseline_sofa, 
        s.peak_sofa, 
        s.delta_sofa,
        a.max_sofa_72h, 
        a.sofa_severity, 
        a.vaso, 
        a.vent,
        a.onset_type, 
        a.died_in_hospital, 
        a.died_30d, 
        a.hospital_los_days,
        ABS(EXTRACT(EPOCH FROM (s.s_onset - a.a_onset))/3600) AS diff_hours,
        ROW_NUMBER() OVER (
            PARTITION BY s.person_id, s.s_onset 
            ORDER BY ABS(EXTRACT(EPOCH FROM (s.s_onset - a.a_onset)))
        ) AS rn_s,
        ROW_NUMBER() OVER (
            PARTITION BY a.person_id, a.a_onset 
            ORDER BY ABS(EXTRACT(EPOCH FROM (s.s_onset - a.a_onset)))
        ) AS rn_a
    FROM s 
    JOIN a USING (person_id)
    WHERE ABS(EXTRACT(EPOCH FROM (s.s_onset - a.a_onset))) <= 72 * 3600
),
-- Keep only mutual best matches (prevents many-to-one)
matches AS (
    SELECT * FROM candidates WHERE rn_s = 1 AND rn_a = 1
)

-- 1. Both cohorts
SELECT 
    person_id, sv, av, s_onset, a_onset, infection_type,
    baseline_sofa, peak_sofa, delta_sofa, 
    max_sofa_72h, sofa_severity, vaso, vent,
    onset_type, died_in_hospital, died_30d, hospital_los_days,
    'both'::text AS cohort_type, 
    diff_hours AS onset_diff_hours
FROM matches

UNION ALL

-- 2. Sepsis-3 only
SELECT 
    s.person_id, s.visit_occurrence_id, NULL, s.s_onset, NULL, s.infection_type,
    s.baseline_sofa, s.peak_sofa, s.delta_sofa, 
    NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL,
    'sepsis3_only'::text, 
    NULL
FROM s 
WHERE NOT EXISTS (
    SELECT 1 FROM matches m 
    WHERE m.person_id = s.person_id AND m.s_onset = s.s_onset
)

UNION ALL

-- 3. ASE only
SELECT 
    a.person_id, NULL, a.visit_occurrence_id, NULL, a.a_onset, NULL,
    NULL, NULL, NULL, 
    a.max_sofa_72h, a.sofa_severity, a.vaso, a.vent,
    a.onset_type, a.died_in_hospital, a.died_30d, a.hospital_los_days,
    'ase_only'::text, 
    NULL
FROM a 
WHERE NOT EXISTS (
    SELECT 1 FROM matches m 
    WHERE m.person_id = a.person_id AND m.a_onset = a.a_onset
);

-- Add indexes for performance
CREATE INDEX idx_sepsis_cohort_person ON results_site_a.sepsis_cohort_comparison(person_id);
CREATE INDEX idx_sepsis_cohort_type ON results_site_a.sepsis_cohort_comparison(cohort_type);

-- Validation query
SELECT 
    cohort_type,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM results_site_a.sepsis_cohort_comparison
GROUP BY cohort_type
ORDER BY n DESC;
