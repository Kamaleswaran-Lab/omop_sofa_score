-- Calculate hourly SOFA scores - MGH FIXED
DROP TABLE IF EXISTS {{results_schema}}.sofa_hourly CASCADE;

CREATE TABLE {{results_schema}}.sofa_hourly AS
SELECT 
    sc.person_id,
    sc.charttime,
    -- Respiratory SOFA
    CASE 
        WHEN sc.pf_ratio >= 400 THEN 0
        WHEN sc.pf_ratio >= 300 THEN 1
        WHEN sc.pf_ratio >= 200 THEN 2
        WHEN sc.pf_ratio >= 100 AND sc.ventilation_status = 1 THEN 3
        WHEN sc.pf_ratio < 100 AND sc.ventilation_status = 1 THEN 4
        WHEN sc.pf_ratio < 200 THEN 2
        ELSE NULL
    END AS resp_sofa,
    -- Cardiovascular SOFA
    CASE 
        WHEN sc.nee_dose > 0.1 THEN 4
        WHEN sc.nee_dose > 0 THEN 3
        WHEN sc.map < 70 THEN 1
        ELSE 0
    END AS cardio_sofa,
    -- Neurological SOFA (no RASS in MGH components, use GCS only)
    CASE 
        WHEN sc.gcs >= 15 THEN 0
        WHEN sc.gcs >= 13 THEN 1
        WHEN sc.gcs >= 10 THEN 2
        WHEN sc.gcs >= 6 THEN 3
        WHEN sc.gcs < 6 THEN 4
        ELSE NULL
    END AS neuro_sofa,
    -- Renal SOFA (MGH: use rrt_status and creatinine; urine_output is hourly)
    CASE 
        WHEN sc.rrt_status = 1 THEN 4
        WHEN sc.creatinine >= 5.0 THEN 4
        WHEN sc.creatinine >= 3.5 THEN 3
        WHEN sc.creatinine >= 2.0 THEN 2
        WHEN sc.creatinine >= 1.2 THEN 1
        WHEN sc.creatinine < 1.2 THEN 0
        ELSE NULL
    END AS renal_sofa,
    -- Hepatic SOFA
    CASE 
        WHEN sc.bilirubin >= 12.0 THEN 4
        WHEN sc.bilirubin >= 6.0 THEN 3
        WHEN sc.bilirubin >= 2.0 THEN 2
        WHEN sc.bilirubin >= 1.2 THEN 1
        WHEN sc.bilirubin < 1.2 THEN 0
        ELSE NULL
    END AS hepatic_sofa,
    -- Coagulation SOFA
    CASE 
        WHEN sc.platelets >= 150 THEN 0
        WHEN sc.platelets >= 100 THEN 1
        WHEN sc.platelets >= 50 THEN 2
        WHEN sc.platelets >= 20 THEN 3
        WHEN sc.platelets < 20 THEN 4
        ELSE NULL
    END AS coag_sofa,
    -- Raw values for audit (map to available columns)
    sc.pf_ratio,
    sc.pao2,
    sc.fio2,
    NULL::numeric AS spo2,
    sc.nee_dose,
    sc.vasopressin_dose,
    sc.dopamine_dose,
    sc.gcs AS gcs_total,
    NULL::numeric AS rass_score,
    sc.creatinine,
    sc.bilirubin,
    sc.platelets,
    sc.lactate,
    sc.urine_output AS urine_24h,
    sc.rrt_status::boolean AS rrt_active,
    sc.ventilation_status::boolean AS ventilated,
    NULL::numeric AS temperature,
    NULL::numeric AS heart_rate,
    sc.sbp,
    sc.dbp,
    sc.map,
    NULL::numeric AS resp_rate
FROM {{results_schema}}.vw_sofa_components sc;

-- Add total SOFA
ALTER TABLE {{results_schema}}.sofa_hourly 
ADD COLUMN total_sofa INTEGER;

UPDATE {{results_schema}}.sofa_hourly
SET total_sofa = 
    COALESCE(resp_sofa, 0) + 
    COALESCE(cardio_sofa, 0) + 
    COALESCE(neuro_sofa, 0) + 
    COALESCE(renal_sofa, 0) + 
    COALESCE(hepatic_sofa, 0) + 
    COALESCE(coag_sofa, 0);

CREATE INDEX idx_sofa_hourly_person_time ON {{results_schema}}.sofa_hourly(person_id, charttime);
