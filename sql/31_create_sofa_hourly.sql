-- Calculate hourly SOFA scores
DROP TABLE IF EXISTS results_site_a.sofa_hourly CASCADE;

CREATE TABLE results_site_a.sofa_hourly AS
SELECT 
    person_id,
    charttime,
    -- Respiratory SOFA
    CASE 
        WHEN pf_ratio >= 400 THEN 0
        WHEN pf_ratio >= 300 THEN 1
        WHEN pf_ratio >= 200 THEN 2
        WHEN pf_ratio >= 100 AND ventilated THEN 3
        WHEN pf_ratio < 100 AND ventilated THEN 4
        WHEN pf_ratio < 200 THEN 2
        ELSE NULL
    END AS resp_sofa,
    -- Cardiovascular SOFA
    CASE 
        WHEN nee_dose > 0.1 THEN 4
        WHEN nee_dose > 0 THEN 3
        WHEN map < 70 THEN 1
        ELSE 0
    END AS cardio_sofa,
    -- Neurological SOFA (RASS-aware)
    CASE 
        WHEN rass_score <= -4 THEN NULL
        WHEN gcs_total >= 15 THEN 0
        WHEN gcs_total >= 13 THEN 1
        WHEN gcs_total >= 10 THEN 2
        WHEN gcs_total >= 6 THEN 3
        WHEN gcs_total < 6 THEN 4
        ELSE NULL
    END AS neuro_sofa,
    -- Renal SOFA
    CASE 
        WHEN rrt_active THEN 4
        WHEN urine_24h < 200 THEN 4
        WHEN urine_24h < 500 THEN 3
        WHEN creatinine >= 5.0 THEN 4
        WHEN creatinine >= 3.5 THEN 3
        WHEN creatinine >= 2.0 THEN 2
        WHEN creatinine >= 1.2 THEN 1
        WHEN creatinine < 1.2 THEN 0
        ELSE NULL
    END AS renal_sofa,
    -- Hepatic SOFA
    CASE 
        WHEN bilirubin >= 12.0 THEN 4
        WHEN bilirubin >= 6.0 THEN 3
        WHEN bilirubin >= 2.0 THEN 2
        WHEN bilirubin >= 1.2 THEN 1
        WHEN bilirubin < 1.2 THEN 0
        ELSE NULL
    END AS hepatic_sofa,
    -- Coagulation SOFA
    CASE 
        WHEN platelets >= 150 THEN 0
        WHEN platelets >= 100 THEN 1
        WHEN platelets >= 50 THEN 2
        WHEN platelets >= 20 THEN 3
        WHEN platelets < 20 THEN 4
        ELSE NULL
    END AS coag_sofa,
    -- Raw values for audit
    pf_ratio,
    pao2,
    fio2,
    spo2,
    nee_dose,
    vasopressin_dose,
    dopamine_dose,
    gcs_total,
    rass_score,
    creatinine,
    bilirubin,
    platelets,
    lactate,
    urine_24h,
    rrt_active,
    ventilated,
    temperature,
    heart_rate,
    sbp,
    dbp,
    map,
    resp_rate
FROM results_site_a.vw_sofa_components;

-- Add total SOFA
ALTER TABLE results_site_a.sofa_hourly 
ADD COLUMN total_sofa INTEGER;

UPDATE results_site_a.sofa_hourly
SET total_sofa = 
    COALESCE(resp_sofa, 0) + 
    COALESCE(cardio_sofa, 0) + 
    COALESCE(neuro_sofa, 0) + 
    COALESCE(renal_sofa, 0) + 
    COALESCE(hepatic_sofa, 0) + 
    COALESCE(coag_sofa, 0);

CREATE INDEX idx_sofa_hourly_person_time ON results_site_a.sofa_hourly(person_id, charttime);