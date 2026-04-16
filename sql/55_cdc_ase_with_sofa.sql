-- 55_cdc_ase_with_sofa.sql
-- Join CDC ASE cases with SOFA scores (using sofa_hourly table)
-- Depends on: cdc_ase_cases, sofa_hourly

DROP TABLE IF EXISTS :results_schema.cdc_ase_with_sofa;

CREATE TABLE :results_schema.cdc_ase_with_sofa AS

WITH ase AS (
    SELECT * FROM :results_schema.cdc_ase_cases
),

sofa_windowed AS (
    SELECT
        s.person_id,
        a.visit_occurrence_id,
        s.charttime::date AS sofa_date,
        s.total_sofa AS sofa_score,
        s.resp_sofa AS resp_score,
        s.coag_sofa AS coag_score,
        s.hepatic_sofa AS liver_score,
        s.cardio_sofa AS cardio_score,
        s.neuro_sofa AS cns_score,
        s.renal_sofa AS renal_score,
        -- Calculate days relative to ASE onset
        (s.charttime::date - a.onset_date) AS day_relative_to_onset
    FROM :results_schema.sofa_hourly s
    JOIN ase a 
        ON s.person_id = a.person_id 
    WHERE s.charttime::date BETWEEN a.onset_date - 2 AND a.onset_date + 7
      AND s.charttime BETWEEN a.visit_start_date AND a.visit_end_date + interval '7 days'
),

sofa_aggregated AS (
    SELECT
        person_id,
        visit_occurrence_id,
        -- Baseline SOFA (day -2 to -1) - use worst value
        MAX(CASE WHEN day_relative_to_onset BETWEEN -2 AND -1 THEN sofa_score END) AS baseline_sofa,
        -- SOFA at onset (day 0)
        MAX(CASE WHEN day_relative_to_onset = 0 THEN sofa_score END) AS sofa_at_onset,
        -- Max SOFA in windows
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 1 THEN sofa_score END) AS max_sofa_24h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 2 THEN sofa_score END) AS max_sofa_48h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN sofa_score END) AS max_sofa_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 7 THEN sofa_score END) AS max_sofa_7d,
        -- Delta SOFA
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN sofa_score END) - 
        MAX(CASE WHEN day_relative_to_onset BETWEEN -2 AND -1 THEN sofa_score END) AS delta_sofa_72h,
        -- Component maxes (72h window)
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN resp_score END) AS max_resp_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN cardio_score END) AS max_cardio_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN renal_score END) AS max_renal_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN coag_score END) AS max_coag_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN liver_score END) AS max_liver_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN cns_score END) AS max_cns_72h
    FROM sofa_windowed
    GROUP BY person_id, visit_occurrence_id
)

SELECT
    a.*,
    s.baseline_sofa,
    s.sofa_at_onset,
    s.max_sofa_24h,
    s.max_sofa_48h,
    s.max_sofa_72h,
    s.max_sofa_7d,
    s.delta_sofa_72h,
    s.max_resp_72h,
    s.max_cardio_72h,
    s.max_renal_72h,
    s.max_coag_72h,
    s.max_liver_72h,
    s.max_cns_72h,
    -- Sepsis-3 criteria (SOFA >=2 increase from baseline)
    CASE 
        WHEN s.delta_sofa_72h >= 2 THEN 1 
        WHEN s.baseline_sofa IS NULL AND s.max_sofa_72h >= 2 THEN 1
        ELSE 0 
    END AS meets_sepsis3,
    -- Severity categories
    CASE
        WHEN s.max_sofa_72h >= 10 THEN 'severe'
        WHEN s.max_sofa_72h >= 6 THEN 'moderate'
        WHEN s.max_sofa_72h >= 2 THEN 'mild'
        WHEN s.max_sofa_72h IS NOT NULL THEN 'minimal'
        ELSE NULL
    END AS sofa_severity
FROM ase a
LEFT JOIN sofa_aggregated s 
    ON s.person_id = a.person_id 
    AND s.visit_occurrence_id = a.visit_occurrence_id;

-- Indexes for performance
CREATE INDEX idx_ase_sofa_person ON :results_schema.cdc_ase_with_sofa (person_id);
CREATE INDEX idx_ase_sofa_visit ON :results_schema.cdc_ase_with_sofa (visit_occurrence_id);
CREATE INDEX idx_ase_sofa_onset ON :results_schema.cdc_ase_with_sofa (onset_date);

ANALYZE :results_schema.cdc_ase_with_sofa;

-- Verification query
SELECT 
    'SOFA Join Summary' AS check_type,
    COUNT(*) AS total_ase_cases,
    COUNT(max_sofa_72h) AS cases_with_sofa,
    ROUND(100.0 * COUNT(max_sofa_72h) / COUNT(*), 1) AS pct_with_sofa,
    ROUND(AVG(max_sofa_72h), 2) AS mean_sofa_72h,
    ROUND(AVG(baseline_sofa), 2) AS mean_baseline
FROM :results_schema.cdc_ase_with_sofa;
