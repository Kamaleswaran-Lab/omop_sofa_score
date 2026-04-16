-- 56_cdc_ase_cohort_final.sql
--  fixes: vasopressor IDs 1343916/1321341, no quantity filter, intubation proxy for vents

DROP TABLE IF EXISTS :results_schema.cdc_ase_cohort_final;

CREATE TABLE :results_schema.cdc_ase_cohort_final AS
WITH ase_base AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        culture_date,
        first_qad_date,
        first_od_date,
        onset_date,
        qad_count,
        od_types,
        visit_start_date,
        visit_end_date,
        visit_concept_id,
        visit_type,
        hospital_day_onset,
        onset_type,
        year,
        baseline_sofa,
        sofa_at_onset,
        max_sofa_24h,
        max_sofa_48h,
        max_sofa_72h,
        max_sofa_7d,
        delta_sofa_72h,
        max_resp_72h,
        max_cardio_72h,
        max_renal_72h,
        max_coag_72h,
        max_liver_72h,
        max_cns_72h,
        meets_sepsis3,
        sofa_severity
    FROM :results_schema.cdc_ase_with_sofa
),
vaso AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS vasopressor_72h
    FROM ase_base a
    INNER JOIN :cdm_schema.drug_exposure de 
        ON de.person_id = a.person_id
        AND de.drug_exposure_start_date >= (a.onset_date - INTERVAL '1 day')
        AND de.drug_exposure_start_date <= (a.onset_date + INTERVAL '2 days')
    WHERE de.drug_concept_id IN (1343916, 1321341)
),
vent AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS mechanical_vent_72h
    FROM ase_base a
    INNER JOIN :cdm_schema.procedure_occurrence po
        ON po.person_id = a.person_id
        AND po.procedure_date >= (a.onset_date - INTERVAL '1 day')
        AND po.procedure_date <= (a.onset_date + INTERVAL '2 days')
    WHERE po.procedure_concept_id IN (4202832, 4058031)
),
icu AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS icu_72h
    FROM ase_base a
    INNER JOIN :cdm_schema.visit_detail vd
        ON vd.person_id = a.person_id
        AND vd.visit_detail_start_date >= (a.onset_date - INTERVAL '1 day')
        AND vd.visit_detail_start_date <= (a.onset_date + INTERVAL '2 days')
    WHERE vd.visit_detail_concept_id IN (32037, 581379, 581476, 3265857, 3265858, 3265859)
),
mortality AS (
    SELECT 
        a.person_id,
        a.visit_occurrence_id,
        CASE 
            WHEN d.death_date IS NOT NULL 
                AND d.death_date >= a.onset_date 
                AND d.death_date <= (a.onset_date + INTERVAL '30 days')
            THEN 1 ELSE 0 
        END AS death_30d,
        CASE 
            WHEN d.death_date IS NOT NULL 
                AND d.death_date >= a.visit_start_date 
                AND d.death_date <= a.visit_end_date
            THEN 1 ELSE 0 
        END AS death_in_hospital
    FROM ase_base a
    LEFT JOIN :cdm_schema.death d 
        ON d.person_id = a.person_id
)
SELECT
    a.person_id,
    a.visit_occurrence_id,
    a.culture_date,
    a.first_qad_date,
    a.first_od_date,
    a.onset_date,
    a.qad_count,
    a.od_types,
    a.visit_start_date,
    a.visit_end_date,
    a.hospital_day_onset,
    a.onset_type,
    a.year,
    a.baseline_sofa,
    a.sofa_at_onset,
    a.max_sofa_24h,
    a.max_sofa_48h,
    a.max_sofa_72h,
    a.max_sofa_7d,
    a.delta_sofa_72h,
    a.max_resp_72h,
    a.max_cardio_72h,
    a.max_renal_72h,
    a.max_coag_72h,
    a.max_liver_72h,
    a.max_cns_72h,
    a.meets_sepsis3,
    a.sofa_severity,
    COALESCE(vs.vasopressor_72h, 0) AS vasopressor_72h,
    COALESCE(vt.mechanical_vent_72h, 0) AS mechanical_vent_72h,
    COALESCE(i.icu_72h, 0) AS icu_72h,
    COALESCE(m.death_30d, 0) AS death_30d,
    COALESCE(m.death_in_hospital, 0) AS death_in_hospital
FROM ase_base a
LEFT JOIN vaso vs 
    ON vs.person_id = a.person_id 
    AND vs.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN vent vt 
    ON vt.person_id = a.person_id 
    AND vt.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN icu i 
    ON i.person_id = a.person_id 
    AND i.visit_occurrence_id = a.visit_occurrence_id
LEFT JOIN mortality m 
    ON m.person_id = a.person_id 
    AND m.visit_occurrence_id = a.visit_occurrence_id;

-- Create indexes
CREATE INDEX idx_ase_final_person ON :results_schema.cdc_ase_cohort_final (person_id);
CREATE INDEX idx_ase_final_visit ON :results_schema.cdc_ase_cohort_final (visit_occurrence_id);
CREATE INDEX idx_ase_final_onset ON :results_schema.cdc_ase_cohort_final (onset_date);

-- Summary statistics
SELECT 
    'Cohort Summary' AS metric,
    COUNT(*) AS total_episodes,
    COUNT(DISTINCT person_id) AS unique_patients,
    ROUND(AVG(max_sofa_72h)::numeric, 2) AS mean_sofa_72h,
    SUM(vasopressor_72h) AS vasopressor_count,
    ROUND((100.0 * SUM(vasopressor_72h) / NULLIF(COUNT(*),0))::numeric, 1) AS vasopressor_pct,
    SUM(mechanical_vent_72h) AS vent_count,
    ROUND((100.0 * SUM(mechanical_vent_72h) / NULLIF(COUNT(*),0))::numeric, 1) AS vent_pct,
    SUM(icu_72h) AS icu_count,
    ROUND((100.0 * SUM(icu_72h) / NULLIF(COUNT(*),0))::numeric, 1) AS icu_pct,
    SUM(death_in_hospital) AS deaths_in_hosp,
    ROUND((100.0 * SUM(death_in_hospital) / NULLIF(COUNT(*),0))::numeric, 1) AS mortality_pct
FROM :results_schema.cdc_ase_cohort_final;
