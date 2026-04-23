-- SEPSIS-3 vs CDC ASE OVERLAP AUDIT - MGH/CHoRUS
-- Assumes: results_site_a.sepsis3_enhanced, results_site_a.cdc_ase_cohort_final, results_site_a.sofa_hourly exist
-- Change schemas at top if needed

WITH
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
    WHERE s.delta_sofa >= 2  -- Sepsis-3 definition
),
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
        a.died_in_hospital,
        a.died_30d,
        a.hospital_los_days
    FROM results_site_a.cdc_ase_cohort_final a
),
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
        CASE 
            WHEN s.person_id IS NOT NULL AND a.person_id IS NOT NULL THEN 'Both'
            WHEN s.person_id IS NOT NULL THEN 'Sepsis3_Only'
            ELSE 'ASE_Only'
        END AS cohort_group,
        ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/3600) AS onset_diff_hours
    FROM sepsis3 s
    FULL OUTER JOIN ase a 
        ON s.person_id = a.person_id
        AND ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/86400) < 3  -- within 3 days
),
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
sofa_at_onset AS (
    SELECT DISTINCT ON (c.person_id)
        c.person_id,
        sh.charttime,
        sh.total_sofa, 
        sh.resp_sofa, sh.cardio_sofa, sh.neuro_sofa,
        sh.renal_sofa, sh.hepatic_sofa, sh.coag_sofa,
        sh.lactate, sh.creatinine, sh.bilirubin, sh.platelets, 
        sh.pf_ratio, sh.nee_dose, sh.map
    FROM cohorts c
    LEFT JOIN results_site_a.sofa_hourly sh 
        ON c.person_id = sh.person_id
        AND sh.charttime BETWEEN 
            COALESCE(c.sepsis3_onset, c.ase_onset) - INTERVAL '12 hours'
            AND COALESCE(c.sepsis3_onset, c.ase_onset) + INTERVAL '12 hours'
    ORDER BY c.person_id, 
             ABS(EXTRACT(EPOCH FROM (sh.charttime - COALESCE(c.sepsis3_onset, c.ase_onset))))
)
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
    d.gender, 
    d.race, 
    d.ethnicity,
    EXTRACT(YEAR FROM COALESCE(c.sepsis3_onset, c.ase_onset)) - d.year_of_birth AS age_at_onset,
    a.died_in_hospital,
    a.died_30d,
    a.hospital_los_days,
    a.vasopressor_72h,
    a.ventilation_72h,
    s.total_sofa,
    s.resp_sofa, s.cardio_sofa, s.neuro_sofa, s.renal_sofa, s.hepatic_sofa, s.coag_sofa,
    s.lactate, s.pf_ratio, s.nee_dose, s.creatinine, s.bilirubin, s.platelets, s.map
FROM cohorts c
LEFT JOIN demographics d USING (person_id)
LEFT JOIN ase a USING (person_id, visit_occurrence_id)
LEFT JOIN sofa_at_onset s USING (person_id);
