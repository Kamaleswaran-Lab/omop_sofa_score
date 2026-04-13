-- 32-field audit table for full provenance
DROP TABLE IF EXISTS results_site_a.sofa_assumptions CASCADE;

CREATE TABLE results_site_a.sofa_assumptions (
    person_id BIGINT,
    visit_occurrence_id BIGINT,
    charttime TIMESTAMP,
    -- SOFA components
    resp_sofa INTEGER,
    cardio_sofa INTEGER,
    neuro_sofa INTEGER,
    renal_sofa INTEGER,
    hepatic_sofa INTEGER,
    coag_sofa INTEGER,
    total_sofa INTEGER,
    -- Respiratory details
    pf_ratio NUMERIC,
    pao2_value NUMERIC,
    fio2_value NUMERIC,
    spo2_value NUMERIC,
    fio2_imputed BOOLEAN DEFAULT FALSE,
    fio2_delta_minutes INTEGER,
    ventilation_status BOOLEAN,
    -- Cardiovascular details
    map_value NUMERIC,
    sbp_value NUMERIC,
    dbp_value NUMERIC,
    nee_total NUMERIC,
    vasopressin_dose NUMERIC,
    dopamine_dose NUMERIC,
    vasopressin_included BOOLEAN DEFAULT TRUE,
    -- Neurological details
    gcs_total INTEGER,
    rass_score INTEGER,
    gcs_method VARCHAR(50),
    -- Renal details
    creatinine_value NUMERIC,
    urine_output_24h NUMERIC,
    rrt_active BOOLEAN,
    -- Hepatic details
    bilirubin_value NUMERIC,
    -- Coagulation details
    platelets_value NUMERIC,
    -- Lactate
    lactate_value NUMERIC,
    -- Baseline tracking
    baseline_sofa INTEGER,
    baseline_method VARCHAR(50),
    delta_sofa INTEGER,
    components_scored INTEGER,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_assumptions_person_time ON results_site_a.sofa_assumptions(person_id, charttime);