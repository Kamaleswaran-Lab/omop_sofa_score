-- 61_create_sepsis_cohort_comparison.sql
-- Compares Sepsis-3 vs CDC ASE cohorts
-- MGH fix: joins on person_id + temporal proximity (not visit_occurrence_id)

DROP TABLE IF EXISTS @results_schema.sepsis_cohort_comparison CASCADE;

CREATE TABLE @results_schema.sepsis_cohort_comparison AS
WITH sepsis3 AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        infection_onset AS sepsis3_onset,
        infection_type,
        baseline_sofa,
        peak_sofa,
        delta_sofa
    FROM @results_schema.sepsis3_enhanced
    WHERE meets_sepsis3 = TRUE
      AND delta_sofa >= 2
      AND baseline_sofa > 0
),
ase AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        infection_onset AS ase_onset,
        onset_date,
        max_sofa_72h,
        sofa_severity,
        vasopressor_72h,
        ventilation_72h,
        onset_type,
        died_in_hospital,
        died_30d,
        hospital_los_days
    FROM @results_schema.cdc_ase_cohort_final
),
best_matches AS (
    SELECT DISTINCT ON (s.person_id, s.sepsis3_onset)
        s.person_id,
        s.visit_occurrence_id AS sepsis3_visit_id,
        a.visit_occurrence_id AS ase_visit_id,
        s.sepsis3_onset,
        a.ase_onset,
        s.infection_type,
        s.baseline_sofa,
        s.peak_sofa,
        s.delta_sofa,
        a.max_sofa_72h,
        a.sofa_severity,
        a.vasopressor_72h,
        a.ventilation_72h,
        a.onset_type,
        a.died_in_hospital,
        a.died_30d,
        a.hospital_los_days,
        ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/3600) AS onset_diff_hours
    FROM sepsis3 s
    JOIN ase a 
      ON s.person_id = a.person_id
     AND ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))) <= 259200
    ORDER BY s.person_id, s.sepsis3_onset, ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset)))
)
SELECT 
    person_id,
    sepsis3_visit_id,
    ase_visit_id,
    sepsis3_onset,
    ase_onset,
    infection_type,
    baseline_sofa,
    peak_sofa,
    delta_sofa,
    max_sofa_72h,
    sofa_severity,
    vasopressor_72h,
    ventilation_72h,
    onset_type,
    died_in_hospital,
    died_30d,
    hospital_los_days,
    'both' AS cohort_type,
    onset_diff_hours
FROM best_matches

UNION ALL

SELECT 
    s.person_id,
    s.visit_occurrence_id AS sepsis3_visit_id,
    NULL AS ase_visit_id,
    s.sepsis3_onset,
    NULL AS ase_onset,
    s.infection_type,
    s.baseline_sofa,
    s.peak_sofa,
    s.delta_sofa,
    NULL AS max_sofa_72h,
    NULL AS sofa_severity,
    NULL AS vasopressor_72h,
    NULL AS ventilation_72h,
    NULL AS onset_type,
    NULL AS died_in_hospital,
    NULL AS died_30d,
    NULL AS hospital_los_days,
    'sepsis3_only' AS cohort_type,
    NULL AS onset_diff_hours
FROM sepsis3 s
WHERE NOT EXISTS (
    SELECT 1 FROM best_matches b 
    WHERE b.person_id = s.person_id 
      AND b.sepsis3_onset = s.sepsis3_onset
)

UNION ALL

SELECT 
    a.person_id,
    NULL AS sepsis3_visit_id,
    a.visit_occurrence_id AS ase_visit_id,
    NULL AS sepsis3_onset,
    a.ase_onset,
    NULL AS infection_type,
    NULL AS baseline_sofa,
    NULL AS peak_sofa,
    NULL AS delta_sofa,
    a.max_sofa_72h,
    a.sofa_severity,
    a.vasopressor_72h,
    a.ventilation_72h,
    a.onset_type,
    a.died_in_hospital,
    a.died_30d,
    a.hospital_los_days,
    'ase_only' AS cohort_type,
    NULL AS onset_diff_hours
FROM ase a
WHERE NOT EXISTS (
    SELECT 1 FROM best_matches b 
    WHERE b.person_id = a.person_id 
      AND b.ase_onset = a.ase_onset
);

CREATE INDEX idx_scc_person ON @results_schema.sepsis_cohort_comparison(person_id);
CREATE INDEX idx_scc_cohort ON @results_schema.sepsis_cohort_comparison(cohort_type);
CREATE INDEX idx_scc_onset ON @results_schema.sepsis_cohort_comparison(sepsis3_onset);
