-- 61_create_sepsis_cohort_comparison.sql
-- Compares Sepsis-3 vs CDC ASE cohorts
-- MGH-fixed: uses infection_onset (not infection_onset_datetime)

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
)
SELECT
    COALESCE(s.person_id, a.person_id) AS person_id,
    COALESCE(s.visit_occurrence_id, a.visit_occurrence_id) AS visit_occurrence_id,
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
    CASE
        WHEN s.person_id IS NOT NULL AND a.person_id IS NOT NULL THEN 'both'
        WHEN s.person_id IS NOT NULL THEN 'sepsis3_only'
        ELSE 'ase_only'
    END AS cohort_type,
    ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/3600) AS onset_diff_hours
FROM sepsis3 s
FULL OUTER JOIN ase a
  ON s.person_id = a.person_id
 AND s.visit_occurrence_id = a.visit_occurrence_id;

CREATE INDEX idx_scc_person ON @results_schema.sepsis_cohort_comparison(person_id);
CREATE INDEX idx_scc_cohort ON @results_schema.sepsis_cohort_comparison(cohort_type);
CREATE INDEX idx_scc_onset ON @results_schema.sepsis_cohort_comparison(sepsis3_onset);
