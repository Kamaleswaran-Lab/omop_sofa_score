-- 56_cdc_ase_cohort_final.sql
-- Final CDC ASE cohort with outcomes, organ support, and mortality
-- FIXED: Uses correct vasopressor concept IDs from vw_vasopressors_nee
-- Depends on: cdc_ase_with_sofa

DROP TABLE IF EXISTS :results_schema.cdc_ase_cohort_final;

CREATE TABLE :results_schema.cdc_ase_cohort_final AS

WITH ase AS (
    SELECT * FROM :results_schema.cdc_ase_with_sofa
),

-- Vasopressors within ±2 days of onset (using actual concept IDs from your DB)
vasopressors AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS received_vasopressor,
        MIN(v.charttime) AS first_vasopressor_time
    FROM ase a
    JOIN :cdm_schema.drug_exposure de 
        ON de.person_id = a.person_id
    WHERE de.drug_concept_id IN (
        -- Norepinephrine (including your 1321341)
        4328749, 1321341, 19010309, 35897581, 4021963,
        -- Epinephrine (including your 1343916)
        1343916, 1338005, 19076899, 19123434, 35897579, 4022245,
        -- Vasopressin
        1360635, 35202042, 35202043, 45775841, 35897584,
        -- Phenylephrine
        1135766, 1335616, 35897582,
        -- Dopamine
        1319998, 1337860, 40240699, 40240703, 35897578, 4022235,
        -- Others
        1337720, 19076659
    )
    AND de.drug_exposure_start_datetime BETWEEN a.onset_date - interval '1 day' AND a.onset_date + interval '2 days'
    AND de.quantity IS NOT NULL
    -- Exclude topical/local (if route info available)
    AND (de.route_concept_id IS NULL OR de.route_concept_id NOT IN (45956875, 4263681)) -- topical, intranasal
    GROUP BY a.person_id, a.visit_occurrence_id
),

-- Mechanical ventilation
ventilation AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS received_ventilation
    FROM ase a
    JOIN :cdm_schema.procedure_occurrence po 
        ON po.person_id = a.person_id
    WHERE po.procedure_concept_id IN (
        4061643,  -- invasive mechanical ventilation
        4230167,  -- endotracheal intubation
        2109225,  -- mechanical ventilation
        2212960,  -- ventilator management
        40481552, -- mechanical ventilation initiation
        4145895   -- ventilation procedures
    )
    AND po.procedure_date BETWEEN a.onset_date - 1 AND a.onset_date + 3
),

-- ICU admission (from visit_detail)
icu_stay AS (
    SELECT DISTINCT
        a.person_id,
        a.visit_occurrence_id,
        1 AS icu_admission,
        MIN(vd.visit_detail_start_datetime) AS icu_start,
        MAX(vd.visit_detail_end_datetime) AS icu_end
    FROM ase a
    JOIN :cdm_schema.visit_detail vd 
        ON vd.visit_occurrence_id = a.visit_occurrence_id
    WHERE vd.visit_detail_concept_id IN (
        32037,    -- Intensive Care
        581379,   -- ICU
        581476,   -- Critical Care
        3265857,  -- Medical ICU
        3265858,  -- Surgical ICU
        3265859,  -- Cardiac ICU
        32037, 581379, 581476, 3265857, 3265858, 3265859
    )
    AND vd.visit_detail_start_date BETWEEN a.onset_date - 1 AND a.onset_date + 7
    GROUP BY a.person_id, a.visit_occurrence_id
),

-- Mortality (in-hospital and 30-day)
mortality AS (
    SELECT
        a.person_id,
        a.visit_occurrence_id,
        -- In-hospital death
        CASE WHEN d.death_date BETWEEN a.visit_start_date AND a.visit_end_date THEN 1 ELSE 0 END AS died_in_hospital,
        -- 30-day mortality
        CASE WHEN d.death_date BETWEEN a.onset_date AND a.onset_date + 30 THEN 1 ELSE 0 END AS died_30d,
        d.death_date,
        d.death_date - a.onset_date AS days_to_death
    FROM ase a
    LEFT JOIN :cdm_schema.death d ON d.person_id = a.person_id
),

-- Lactate (worst in first 24h)
lactate AS (
    SELECT
        a.person_id,
        a.visit_occurrence_id,
        MAX(m.value_as_number) AS max_lactate_24h
    FROM ase a
    JOIN :cdm_schema.measurement m ON m.person_id = a.person_id
    WHERE m.measurement_concept_id IN (3024561, 3031125, 3016723)  -- lactate
    AND m.measurement_datetime BETWEEN a.onset_date AND a.onset_date + interval '1 day'
    AND m.value_as_number BETWEEN 0.1 AND 30  -- plausible range
    GROUP BY a.person_id, a.visit_occurrence_id
)

SELECT
    a.*,
    COALESCE(v.received_vasopressor, 0) AS vasopressor_72h,
    v.first_vasopressor_time,
    COALESCE(vent.received_ventilation, 0) AS ventilation_72h,
    COALESCE(icu.icu_admission, 0) AS icu_admission,
    icu.icu_start,
    icu.icu_end,
    m.died_in_hospital,
    m.died_30d,
    m.death_date,
    m.days_to_death,
    l.max_lactate_24h,
    -- Composite outcomes
    CASE WHEN COALESCE(v.received_vasopressor,0) = 1 OR COALESCE(vent.received_ventilation,0) = 1 
         THEN 1 ELSE 0 END AS organ_support,
    CASE WHEN m.died_in_hospital = 1 OR m.died_30d = 1 THEN 1 ELSE 0 END AS mortality_composite,
    -- Length of stay
    (a.visit_end_date - a.visit_start_date + 1) AS hospital_los_days,
    CASE WHEN icu.icu_end IS NOT NULL 
         THEN EXTRACT(EPOCH FROM (icu.icu_end - icu.icu_start))/86400.0
         ELSE NULL END AS icu_los_days
FROM ase a
LEFT JOIN vasopressors v USING (person_id, visit_occurrence_id)
LEFT JOIN ventilation vent USING (person_id, visit_occurrence_id)
LEFT JOIN icu_stay icu USING (person_id, visit_occurrence_id)
LEFT JOIN mortality m USING (person_id, visit_occurrence_id)
LEFT JOIN lactate l USING (person_id, visit_occurrence_id);

-- Indexes
CREATE INDEX idx_final_person ON :results_schema.cdc_ase_cohort_final (person_id);
CREATE INDEX idx_final_visit ON :results_schema.cdc_ase_cohort_final (visit_occurrence_id);
CREATE INDEX idx_final_onset ON :results_schema.cdc_ase_cohort_final (onset_date);
CREATE INDEX idx_final_severity ON :results_schema.cdc_ase_cohort_final (sofa_severity);

ANALYZE :results_schema.cdc_ase_cohort_final;

-- Summary statistics
SELECT 
    'Cohort Summary' AS metric,
    COUNT(*) AS total_episodes,
    COUNT(DISTINCT person_id) AS unique_patients,
    ROUND(AVG(max_sofa_72h),2) AS mean_sofa_72h,
    SUM(vasopressor_72h) AS vasopressor_count,
    ROUND(100.0 * SUM(vasopressor_72h) / NULLIF(COUNT(*),0),1) AS vasopressor_pct,
    SUM(ventilation_72h) AS vent_count,
    ROUND(100.0 * SUM(ventilation_72h) / NULLIF(COUNT(*),0),1) AS vent_pct,
    SUM(icu_admission) AS icu_count,
    ROUND(100.0 * SUM(icu_admission) / NULLIF(COUNT(*),0),1) AS icu_pct,
    SUM(died_in_hospital) AS deaths_in_hosp,
    ROUND(100.0 * SUM(died_in_hospital) / NULLIF(COUNT(*),0),1) AS mortality_pct
FROM :results_schema.cdc_ase_cohort_final;
