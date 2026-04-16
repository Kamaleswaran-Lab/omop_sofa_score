-- 56_cdc_ase_cohort_final_MGH.sql
-- Final CDC ASE cohort with MGH-specific concept IDs
-- Fixes: vasopressor quantity NULL, non-standard epinephrine ID, intubation proxy for ventilation
 

DROP TABLE IF EXISTS :results_schema.cdc_ase_cohort_final;
CREATE TABLE :results_schema.cdc_ase_cohort_final AS
WITH ase_base AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        onset_date,
        antibiotic_date,
        culture_date,
        sofa_score,
        sofa_72h_max,
        sofa_72h_mean
    FROM :results_schema.cdc_ase_with_sofa
),
vaso AS (
    -- MGH FIX: Use 1343916 (epi) + 1321341 (norepi), NO quantity filter
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS vasopressor_72h
    FROM ase_base a
    JOIN :cdm_schema.drug_exposure de 
        ON de.person_id = a.person_id
        AND de.drug_exposure_start_datetime >= a.onset_date - interval '1 day'
        AND de.drug_exposure_start_datetime <= a.onset_date + interval '2 days'
    WHERE de.drug_concept_id IN (1343916, 1321341)
),
vent AS (
    -- MGH FIX: Use intubation codes (no mechanical vent codes exist)
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS mechanical_vent_72h
    FROM ase_base a
    JOIN :cdm_schema.procedure_occurrence po
        ON po.person_id = a.person_id
        AND po.procedure_datetime >= a.onset_date - interval '1 day'
        AND po.procedure_datetime <= a.onset_date + interval '2 days'
    WHERE po.procedure_concept_id IN (4202832, 4058031)
),
icu AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS icu_72h
    FROM ase_base a
    JOIN :cdm_schema.visit_detail vd
        ON vd.person_id = a.person_id
        AND vd.visit_detail_start_datetime >= a.onset_date - interval '1 day'
        AND vd.visit_detail_start_datetime <= a.onset_date + interval '2 days'
    WHERE vd.visit_detail_concept_id IN (32037, 581379, 581476, 3265857, 3265858, 3265859)
),
mortality AS (
    SELECT 
        a.person_id,
        a.visit_occurrence_id,
        CASE WHEN d.death_datetime BETWEEN a.onset_date AND a.onset_date + interval '30 days'
            THEN 1 ELSE 0 END AS death_30d,
        CASE WHEN d.death_datetime BETWEEN v.visit_start_datetime AND v.visit_end_datetime
            THEN 1 ELSE 0 END AS death_in_hospital
    FROM ase_base a
    JOIN :cdm_schema.visit_occurrence v 
        ON v.visit_occurrence_id = a.visit_occurrence_id
    LEFT JOIN :cdm_schema.death d ON d.person_id = a.person_id
)
SELECT
    a.person_id,
    a.visit_occurrence_id,
    a.onset_date,
    a.antibiotic_date,
    a.culture_date,
    a.sofa_score AS sofa_baseline,
    a.sofa_72h_max,
    a.sofa_72h_mean,
    COALESCE(vs.vasopressor_72h, 0) AS vasopressor_72h,
    COALESCE(vt.mechanical_vent_72h, 0) AS mechanical_vent_72h,
    COALESCE(i.icu_72h, 0) AS icu_72h,
    m.death_30d,
    m.death_in_hospital,
    EXTRACT(EPOCH FROM (a.onset_date - v.visit_start_datetime))/3600 AS hours_to_onset
FROM ase_base a
JOIN :cdm_schema.visit_occurrence v ON v.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN vaso vs ON vs.person_id = a.person_id AND vs.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN vent vt ON vt.person_id = a.person_id AND vt.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN icu i ON i.person_id = a.person_id AND i.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN mortality m ON m.person_id = a.person_id AND m.visit_occurrence_id = a.visit_occurrence_id;

-- Summary
SELECT 
    'Cohort Summary' AS metric,
    COUNT(*) AS total_episodes,
    COUNT(DISTINCT person_id) AS unique_patients,
    ROUND(AVG(sofa_72h_mean),2) AS mean_sofa_72h,
    SUM(vasopressor_72h) AS vasopressor_count,
    ROUND(100.0 * SUM(vasopressor_72h) / COUNT(*), 1) AS vasopressor_pct,
    SUM(mechanical_vent_72h) AS vent_count,
    ROUND(100.0 * SUM(mechanical_vent_72h) / COUNT(*), 1) AS vent_pct,
    SUM(icu_72h) AS icu_count,
    ROUND(100.0 * SUM(icu_72h) / COUNT(*), 1) AS icu_pct,
    SUM(death_in_hospital) AS deaths_in_hosp,
    ROUND(100.0 * SUM(death_in_hospital) / COUNT(*), 1) AS mortality_pct
FROM :results_schema.cdc_ase_cohort_final;
