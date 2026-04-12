-- OMOP SOFA v4.4 - Calculate SOFA components hourly

DROP VIEW IF EXISTS results.v_sofa_components CASCADE;

CREATE VIEW results.v_sofa_components AS
WITH hourly_grid AS (
    SELECT 
        v.person_id,
        v.visit_occurrence_id,
        generate_series(
            v.visit_start_datetime, 
            LEAST(v.visit_end_datetime, v.visit_start_datetime + INTERVAL '30 days'),
            INTERVAL '1 hour'
        ) AS charttime
    FROM cdm.visit_occurrence v
    WHERE v.visit_concept_id = 32037  -- ICU
)
SELECT 
    hg.person_id,
    hg.visit_occurrence_id,
    hg.charttime,
    
    -- Respiratory (FIX #2, #3)
    CASE 
        WHEN pf.pf_ratio < 100 AND vent.person_id IS NOT NULL THEN 4
        WHEN pf.pf_ratio < 200 AND vent.person_id IS NOT NULL THEN 3
        WHEN pf.pf_ratio < 300 THEN 2
        WHEN pf.pf_ratio < 400 THEN 1
        ELSE 0
    END AS resp_score,
    pf.pf_ratio,
    pf.delta_minutes AS fio2_delta,
    
    -- Cardiovascular (FIX #1)
    CASE
        WHEN vp.nee_total >= 0.1 THEN 4
        WHEN vp.nee_total >= 0.05 THEN 3
        WHEN vp.nee_total > 0 THEN 2
        WHEN map.map_value < 70 THEN 1
        ELSE 0
    END AS cardio_score,
    vp.nee_total,
    vp.vasopressin_dose,
    
    -- Neurological (FIX #4)
    CASE
        WHEN neuro.rass_score <= -4 THEN NULL  -- Sedated, don't score
        WHEN neuro.gcs_total >= 15 THEN 0
        WHEN neuro.gcs_total >= 13 THEN 1
        WHEN neuro.gcs_total >= 10 THEN 2
        WHEN neuro.gcs_total >= 6 THEN 3
        WHEN neuro.gcs_total < 6 THEN 4
        ELSE NULL
    END AS neuro_score,
    neuro.gcs_total,
    neuro.rass_score,
    
    -- Renal (FIX #6)
    CASE
        WHEN rrt.person_id IS NOT NULL THEN 4
        WHEN urine.urine_24h_rolling_ml < 200 THEN 4
        WHEN urine.urine_24h_rolling_ml < 500 THEN 3
        WHEN creat.creatinine >= 5.0 THEN 4
        WHEN creat.creatinine >= 3.5 THEN 3
        WHEN creat.creatinine >= 2.0 THEN 2
        WHEN creat.creatinine >= 1.2 THEN 1
        ELSE 0
    END AS renal_score,
    urine.urine_24h_rolling_ml,
    creat.creatinine,
    
    -- Hepatic
    CASE
        WHEN bili.bilirubin >= 12.0 THEN 4
        WHEN bili.bilirubin >= 6.0 THEN 3
        WHEN bili.bilirubin >= 2.0 THEN 2
        WHEN bili.bilirubin >= 1.2 THEN 1
        ELSE 0
    END AS hepatic_score,
    bili.bilirubin,
    
    -- Coagulation
    CASE
        WHEN plt.platelets < 20 THEN 4
        WHEN plt.platelets < 50 THEN 3
        WHEN plt.platelets < 100 THEN 2
        WHEN plt.platelets < 150 THEN 1
        ELSE 0
    END AS coag_score,
    plt.platelets

FROM hourly_grid hg

-- Respiratory data
LEFT JOIN LATERAL (
    SELECT pf_ratio, delta_minutes 
    FROM results.v_pao2_fio2_pairs
    WHERE person_id = hg.person_id 
    AND pao2_time <= hg.charttime
    ORDER BY pao2_time DESC 
    LIMIT 1
) pf ON true

LEFT JOIN LATERAL (
    SELECT person_id FROM results.v_ventilation
    WHERE person_id = hg.person_id 
    AND start_time <= hg.charttime 
    AND end_time >= hg.charttime
    LIMIT 1
) vent ON true

-- Cardiovascular data
LEFT JOIN LATERAL (
    SELECT 
        SUM(nee_contribution) AS nee_total,
        SUM(CASE WHEN is_vasopressin THEN dose_normalized ELSE 0 END) AS vasopressin_dose
    FROM results.v_vasopressors_nee
    WHERE person_id = hg.person_id 
    AND drug_exposure_start_datetime <= hg.charttime
    AND (drug_exposure_end_datetime IS NULL OR drug_exposure_end_datetime >= hg.charttime)
) vp ON true

LEFT JOIN LATERAL (
    SELECT value_as_number AS map_value
    FROM cdm.measurement
    WHERE person_id = hg.person_id
    AND measurement_concept_id = 3027598  -- MAP
    AND measurement_datetime <= hg.charttime
    ORDER BY measurement_datetime DESC
    LIMIT 1
) map ON true

-- Neurological data
LEFT JOIN LATERAL (
    SELECT gcs_total, rass_score
    FROM results.v_neuro_assessment
    WHERE person_id = hg.person_id 
    AND observation_datetime <= hg.charttime
    ORDER BY observation_datetime DESC 
    LIMIT 1
) neuro ON true

-- Renal data
LEFT JOIN LATERAL (
    SELECT urine_24h_rolling_ml
    FROM results.v_urine_24h
    WHERE person_id = hg.person_id 
    AND measurement_datetime <= hg.charttime
    ORDER BY measurement_datetime DESC 
    LIMIT 1
) urine ON true

LEFT JOIN LATERAL (
    SELECT value_as_number AS creatinine
    FROM results.v_labs_core
    WHERE person_id = hg.person_id 
    AND lab_type = 'creatinine'
    AND measurement_datetime <= hg.charttime
    ORDER BY measurement_datetime DESC 
    LIMIT 1
) creat ON true

LEFT JOIN LATERAL (
    SELECT person_id FROM results.v_rrt
    WHERE person_id = hg.person_id 
    AND rrt_start <= hg.charttime
    LIMIT 1
) rrt ON true

-- Hepatic data
LEFT JOIN LATERAL (
    SELECT value_as_number AS bilirubin
    FROM results.v_labs_core
    WHERE person_id = hg.person_id 
    AND lab_type = 'bilirubin'
    AND measurement_datetime <= hg.charttime
    ORDER BY measurement_datetime DESC 
    LIMIT 1
) bili ON true

-- Coagulation data
LEFT JOIN LATERAL (
    SELECT value_as_number AS platelets
    FROM results.v_labs_core
    WHERE person_id = hg.person_id 
    AND lab_type = 'platelets'
    AND measurement_datetime <= hg.charttime
    ORDER BY measurement_datetime DESC 
    LIMIT 1
) plt ON true;

SELECT 'SOFA components view created' AS status;
