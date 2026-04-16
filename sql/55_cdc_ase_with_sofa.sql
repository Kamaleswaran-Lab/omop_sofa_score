-- 55_cdc_ase_with_sofa.sql
-- Join CDC ASE cases with SOFA scores and calculate severity windows
-- Depends on: cdc_ase_cases, sofa_scores (from omop_sofa_score pipeline)

DROP TABLE IF EXISTS :results_schema.cdc_ase_with_sofa;

CREATE TABLE :results_schema.cdc_ase_with_sofa AS

WITH ase AS (
    SELECT * FROM :results_schema.cdc_ase_cases
),

sofa_windowed AS (
    SELECT
        s.person_id,
        s.visit_occurrence_id,
        s.sofa_date,
        s.sofa_score,
        s.resp_score,
        s.coag_score,
        s.liver_score,
        s.cardio_score,
        s.cns_score,
        s.renal_score,
        -- Calculate days relative to ASE onset
        s.sofa_date - a.onset_date AS day_relative_to_onset
    FROM :results_schema.sofa_scores s
    JOIN ase a 
        ON s.person_id = a.person_id 
        AND s.visit_occurrence_id = a.visit_occurrence_id
    WHERE s.sofa_date BETWEEN a.onset_date - 2 AND a.onset_date + 7
),

sofa_aggregated AS (
    SELECT
        person_id,
        visit_occurrence_id,
        -- Baseline SOFA (day -2 to -1)
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
        -- Component maxes
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN resp_score END) AS max_resp_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN cardio_score END) AS max_cardio_72h,
        MAX(CASE WHEN day_relative_to_onset BETWEEN 0 AND 3 THEN renal_score END) AS max_renal_72h
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
    -- Sepsis-3 criteria (SOFA >=2 increase)
    CASE 
        WHEN s.delta_sofa_72h >= 2 THEN 1 
        ELSE 0 
    END AS meets_sepsis3,
    -- Severity categories
    CASE
        WHEN s.max_sofa_72h >= 10 THEN 'severe'
        WHEN s.max_sofa_72h >= 6 THEN 'moderate'
        WHEN s.max_sofa_72h >= 2 THEN 'mild'
        ELSE 'minimal'
    END AS sofa_severity
FROM ase a
LEFT JOIN sofa_aggregated s 
    USING (person_id, visit_occurrence_id);

-- Indexes for performance
CREATE INDEX idx_ase_sofa_person ON :results_schema.cdc_ase_with_sofa (person_id);
CREATE INDEX idx_ase_sofa_visit ON :results_schema.cdc_ase_with_sofa (visit_occurrence_id);
CREATE INDEX idx_ase_sofa_onset ON :results_schema.cdc_ase_with_sofa (onset_date);

ANALYZE :results_schema.cdc_ase_with_sofa;
