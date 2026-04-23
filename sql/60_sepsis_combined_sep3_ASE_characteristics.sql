-- SEPSIS-3 vs CDC ASE OVERLAP AUDIT - CHoRUS (FIXED FOR ACTUAL COLUMNS)
-- Replaces original 60_sepsis_combined_sep3_ASE_characteristics.sql
-- Uses: results_site_a.sepsis3_enhanced (person_id, infection_onset, baseline_sofa, peak_sofa, delta_sofa)
-- results_site_a.cdc_ase_cohort_final (person_id, visit_occurrence_id, onset_date, max_sofa_72h...)

WITH
-- 1. Sepsis-3 cohort (enhanced version)
sepsis3 AS (
    SELECT
        s.person_id,
        s.infection_onset AS sepsis3_onset,
        s.baseline_sofa,
        s.peak_sofa,
        s.delta_sofa,
        s.infection_type,
        s.icu_onset
    FROM results_site_a.sepsis3_enhanced s
    WHERE s.delta_sofa >= 2
),

-- 2. CDC ASE cohort (final)
ase AS (
    SELECT
        a.person_id,
        a.visit_occurrence_id,
        a.onset_date AS ase_onset,
        a.infection_onset AS ase_infection_onset,
        a.max_sofa_72h,
        a.sofa_severity,
        a.vasopressor_72h,
        a.ventilation_72h,
        a.organ_support,
        a.died_in_hospital,
        a.died_30d,
        a.hospital_los_days,
        a.icu_admission
    FROM results_site_a.cdc_ase_cohort_final a
),

-- 3. Overlap classification (join on person_id + onset within 3 days)
cohorts AS (
    SELECT
        COALESCE(s.person_id, a.person_id) AS person_id,
        a.visit_occurrence_id,
        s.sepsis3_onset,
        a.ase_onset,
        s.baseline_sofa,
        s.peak_sofa,
        s.delta_sofa,
        a.max_sofa_72h,
        s.infection_type,
        a.sofa_severity,
        a.vasopressor_72h,
        a.ventilation_72h,
        a.died_in_hospital,
        a.died_30d,
        a.hospital_los_days,
        CASE
            WHEN s.person_id IS NOT NULL AND a.person_id IS NOT NULL THEN 'Both'
            WHEN s.person_id IS NOT NULL THEN 'Sepsis3_Only'
            ELSE 'ASE_Only'
        END AS cohort_group,
        ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/3600) AS onset_diff_hours
    FROM sepsis3 s
    FULL OUTER JOIN ase a
        ON s.person_id = a.person_id
        AND ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))) < 259200 -- 3 days
),

-- 4. Demographics from OMOP
demographics AS (
    SELECT
        p.person_id,
        p.year_of_birth,
        c1.concept_name AS gender,
        c2.concept_name AS race,
        c3.concept_name AS ethnicity
    FROM omopcdm.person p
    LEFT JOIN omopcdm.concept c1 ON p.gender_concept_id = c1.concept_id
    LEFT JOIN omopcdm.concept c2 ON p.race_concept_id = c2.concept_id
    LEFT JOIN omopcdm.concept c3 ON p.ethnicity_concept_id = c3.concept_id
),

-- 5. SOFA at onset (closest hourly SOFA within 12h)
sofa_at_onset AS (
    SELECT DISTINCT ON (c.person_id)
        c.person_id,
        sh.charttime,
        sh.total_sofa,
        sh.resp_sofa,
        sh.cardio_sofa,
        sh.neuro_sofa,
        sh.renal_sofa,
        sh.hepatic_sofa,
        sh.coag_sofa,
        sh.lactate,
        sh.creatinine,
        sh.bilirubin,
        sh.platelets,
        sh.pf_ratio,
        sh.nee_dose,
        sh.map
    FROM cohorts c
    LEFT JOIN results_site_a.sofa_hourly sh
        ON c.person_id = sh.person_id
        AND sh.charttime BETWEEN
            COALESCE(c.sepsis3_onset, c.ase_onset) - INTERVAL '12 hours'
            AND COALESCE(c.sepsis3_onset, c.ase_onset) + INTERVAL '12 hours'
    ORDER BY c.person_id,
             ABS(EXTRACT(EPOCH FROM (sh.charttime - COALESCE(c.sepsis3_onset, c.ase_onset))))
),

-- 6. Final patient-level table
final_cohort AS (
    SELECT
        c.person_id,
        c.visit_occurrence_id,
        c.cohort_group,
        c.sepsis3_onset,
        c.ase_onset,
        c.onset_diff_hours,
        c.baseline_sofa,
        c.peak_sofa,
        c.delta_sofa,
        c.max_sofa_72h,
        c.infection_type,
        c.sofa_severity,
        c.vasopressor_72h,
        c.ventilation_72h,
        c.died_in_hospital,
        c.died_30d,
        c.hospital_los_days,
        d.gender,
        d.race,
        d.ethnicity,
        EXTRACT(YEAR FROM COALESCE(c.sepsis3_onset, c.ase_onset)) - d.year_of_birth AS age_at_onset,
        s.total_sofa,
        s.resp_sofa,
        s.cardio_sofa,
        s.neuro_sofa,
        s.renal_sofa,
        s.hepatic_sofa,
        s.coag_sofa,
        s.lactate,
        s.pf_ratio,
        s.nee_dose,
        s.creatinine,
        s.bilirubin,
        s.platelets,
        s.map
    FROM cohorts c
    LEFT JOIN demographics d USING (person_id)
    LEFT JOIN sofa_at_onset s USING (person_id)
)

-- OUTPUT 1: Counts
SELECT 'Cohort counts' AS output_type, cohort_group,
       COUNT(DISTINCT person_id) AS patients,
       COUNT(*) AS episodes
FROM final_cohort
GROUP BY cohort_group

UNION ALL

SELECT 'Cohort counts', 'TOTAL',
       COUNT(DISTINCT person_id),
       COUNT(*)
FROM final_cohort

ORDER BY cohort_group;

-- OUTPUT 2: Patient-level data
SELECT * FROM final_cohort
ORDER BY cohort_group, person_id;

-- OUTPUT 3: Summary characteristics by group
SELECT
    cohort_group,
    COUNT(*) AS n,
    ROUND(AVG(age_at_onset),1) AS mean_age,
    ROUND(AVG(total_sofa),2) AS mean_sofa,
    ROUND(100.0*SUM(CASE WHEN gender='FEMALE' THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),1) AS pct_female,
    ROUND(100.0*AVG(died_in_hospital),1) AS pct_hosp_mortality,
    ROUND(100.0*AVG(died_30d),1) AS pct_30d_mortality,
    ROUND(AVG(hospital_los_days),1) AS mean_los_days,
    ROUND(100.0*AVG(CASE WHEN vasopressor_72h THEN 1 ELSE 0 END),1) AS pct_vasopressor,
    ROUND(100.0*AVG(CASE WHEN ventilation_72h THEN 1 ELSE 0 END),1) AS pct_ventilation,
    ROUND(AVG(lactate),2) AS mean_lactate,
    ROUND(AVG(pf_ratio),0) AS mean_pf_ratio,
    ROUND(AVG(peak_sofa),1) AS mean_peak_sofa_sepsis3,
    ROUND(AVG(max_sofa_72h),1) AS mean_max_sofa_ase
FROM final_cohort
GROUP BY cohort_group
ORDER BY cohort_group;
