-- SEPSIS-3 vs CDC ASE OVERLAP AUDIT - MGH/CHoRUS
-- Assumes: results_site_a.sepsis3_enhanced, results_site_a.cdc_ase_cohort_final, results_site_a.sofa_hourly exist
-- Change schemas at top if needed

WITH params AS (
    SELECT 
        'results_site_a'::text AS results_schema,
        'omopcdm'::text AS cdm_schema
),

-- 1. Sepsis-3 cohort (enhanced version)
sepsis3 AS (
    SELECT 
        s.person_id,
        s.visit_occurrence_id,
        s.infection_onset_datetime AS sepsis3_onset,
        s.sofa_baseline,
        s.sofa_max_48h,
        s.delta_sofa,
        s.meets_sepsis3
    FROM results_site_a.sepsis3_enhanced s
    WHERE s.meets_sepsis3 = TRUE
),

-- 2. CDC ASE cohort (final)
ase AS (
    SELECT 
        a.person_id,
        a.visit_occurrence_id,
        a.ase_onset_datetime AS ase_onset,
        a.qad_start,
        a.organ_dysfunction_date,
        a.blood_culture_positive
    FROM results_site_a.cdc_ase_cohort_final a
),

-- 3. Overlap classification
cohorts AS (
    SELECT
        COALESCE(s.person_id, a.person_id) AS person_id,
        COALESCE(s.visit_occurrence_id, a.visit_occurrence_id) AS visit_occurrence_id,
        s.sepsis3_onset,
        a.ase_onset,
        CASE 
            WHEN s.person_id IS NOT NULL AND a.person_id IS NOT NULL THEN 'Both'
            WHEN s.person_id IS NOT NULL THEN 'Sepsis3_Only'
            ELSE 'ASE_Only'
        END AS cohort_group,
        -- time difference if both
        ABS(EXTRACT(EPOCH FROM (s.sepsis3_onset - a.ase_onset))/3600) AS onset_diff_hours
    FROM sepsis3 s
    FULL OUTER JOIN ase a 
        ON s.person_id = a.person_id 
        AND s.visit_occurrence_id = a.visit_occurrence_id
),

-- 4. Demographics from OMOP
demographics AS (
    SELECT
        p.person_id,
        p.year_of_birth,
        EXTRACT(YEAR FROM CURRENT_DATE) - p.year_of_birth AS age_current,
        c1.concept_name AS gender,
        c2.concept_name AS race,
        c3.concept_name AS ethnicity
    FROM omopcdm.person p
    LEFT JOIN omopcdm.concept c1 ON p.gender_concept_id = c1.concept_id
    LEFT JOIN omopcdm.concept c2 ON p.race_concept_id = c2.concept_id
    LEFT JOIN omopcdm.concept c3 ON p.ethnicity_concept_id = c3.concept_id
),

-- 5. Visit details + outcomes
visits AS (
    SELECT
        v.person_id,
        v.visit_occurrence_id,
        v.visit_start_datetime,
        v.visit_end_datetime,
        EXTRACT(EPOCH FROM (v.visit_end_datetime - v.visit_start_datetime))/3600/24 AS hospital_los_days,
        v.discharge_to_concept_id,
        d.death_datetime,
        CASE WHEN d.person_id IS NOT NULL THEN 1 ELSE 0 END AS died_in_hospital,
        CASE WHEN d.death_datetime <= v.visit_start_datetime + INTERVAL '30 days' THEN 1 ELSE 0 END AS died_30d
    FROM omopcdm.visit_occurrence v
    LEFT JOIN omopcdm.death d ON v.person_id = d.person_id
        AND d.death_datetime BETWEEN v.visit_start_datetime AND v.visit_end_datetime + INTERVAL '30 days'
),

-- 6. SOFA at onset (use closest hourly SOFA within 6h)
sofa_at_onset AS (
    SELECT DISTINCT ON (c.person_id, c.visit_occurrence_id)
        c.person_id,
        c.visit_occurrence_id,
        c.cohort_group,
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
        sh.nee_dose
    FROM cohorts c
    LEFT JOIN results_site_a.sofa_hourly sh
        ON c.person_id = sh.person_id
        AND sh.charttime BETWEEN 
            COALESCE(c.sepsis3_onset, c.ase_onset) - INTERVAL '6 hours'
            AND COALESCE(c.sepsis3_onset, c.ase_onset) + INTERVAL '6 hours'
    ORDER BY c.person_id, c.visit_occurrence_id, 
             ABS(EXTRACT(EPOCH FROM (sh.charttime - COALESCE(c.sepsis3_onset, c.ase_onset))))
),

-- 7. Comorbidities (Elixhauser/Charlson proxy - prior year)
comorbidities AS (
    SELECT
        c.person_id,
        c.visit_occurrence_id,
        COUNT(DISTINCT CASE WHEN co.condition_concept_id IN (201826, 319835) THEN co.condition_concept_id END) >0 AS diabetes,
        COUNT(DISTINCT CASE WHEN co.condition_concept_id IN (316139, 319844) THEN co.condition_concept_id END) >0 AS chf,
        COUNT(DISTINCT CASE WHEN co.condition_concept_id IN (321052, 318443) THEN co.condition_concept_id END) >0 AS renal_disease,
        COUNT(DISTINCT CASE WHEN co.condition_concept_id IN (317576, 312038) THEN co.condition_concept_id END) >0 AS malignancy,
        COUNT(DISTINCT CASE WHEN co.condition_concept_id IN (255573, 321319) THEN co.condition_concept_id END) >0 AS liver_disease
    FROM cohorts c
    LEFT JOIN omopcdm.condition_occurrence co
        ON c.person_id = co.person_id
        AND co.condition_start_datetime < COALESCE(c.sepsis3_onset, c.ase_onset)
        AND co.condition_start_datetime >= COALESCE(c.sepsis3_onset, c.ase_onset) - INTERVAL '1 year'
    GROUP BY 1,2
),

-- 8. Final patient-level table
final_cohort AS (
    SELECT
        c.person_id,
        c.visit_occurrence_id,
        c.cohort_group,
        c.sepsis3_onset,
        c.ase_onset,
        c.onset_diff_hours,
        d.gender,
        d.race,
        d.ethnicity,
        EXTRACT(YEAR FROM COALESCE(c.sepsis3_onset, c.ase_onset)) - d.year_of_birth AS age_at_onset,
        v.hospital_los_days,
        v.died_in_hospital,
        v.died_30d,
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
        cm.diabetes,
        cm.chf,
        cm.renal_disease,
        cm.malignancy,
        cm.liver_disease
    FROM cohorts c
    LEFT JOIN demographics d USING (person_id)
    LEFT JOIN visits v USING (person_id, visit_occurrence_id)
    LEFT JOIN sofa_at_onset s USING (person_id, visit_occurrence_id, cohort_group)
    LEFT JOIN comorbidities cm USING (person_id, visit_occurrence_id)
)

-- OUTPUT 1: Counts
SELECT 'Cohort counts' AS table_type, * FROM (
    SELECT cohort_group, COUNT(DISTINCT person_id) AS patients, COUNT(*) AS episodes
    FROM final_cohort
    GROUP BY cohort_group
    UNION ALL
    SELECT 'TOTAL', COUNT(DISTINCT person_id), COUNT(*) FROM final_cohort
) ORDER BY cohort_group;

-- OUTPUT 2: Patient-level data (save this)
SELECT * FROM final_cohort
ORDER BY cohort_group, person_id;

-- OUTPUT 3: Summary characteristics by group
SELECT
    cohort_group,
    COUNT(*) AS n,
    ROUND(AVG(age_at_onset),1) AS mean_age,
    ROUND(AVG(total_sofa),2) AS mean_sofa,
    ROUND(100.0*SUM(CASE WHEN gender='FEMALE' THEN 1 ELSE 0 END)/COUNT(*),1) AS pct_female,
    ROUND(100.0*AVG(died_in_hospital),1) AS pct_hosp_mortality,
    ROUND(100.0*AVG(died_30d),1) AS pct_30d_mortality,
    ROUND(AVG(hospital_los_days),1) AS mean_los_days,
    ROUND(100.0*AVG(diabetes::int),1) AS pct_diabetes,
    ROUND(100.0*AVG(chf::int),1) AS pct_chf,
    ROUND(100.0*AVG(renal_disease::int),1) AS pct_renal,
    ROUND(AVG(lactate),2) AS mean_lactate,
    ROUND(AVG(pf_ratio),0) AS mean_pf_ratio
FROM final_cohort
GROUP BY cohort_group;
