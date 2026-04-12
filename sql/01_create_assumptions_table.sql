-- OMOP SOFA v4.4 - Assumptions audit table
-- FIX #10: Expanded from 15 to 32 fields for full provenance

DROP TABLE IF EXISTS results.sofa_assumptions CASCADE;

CREATE TABLE results.sofa_assumptions (
    -- Identifiers
    person_id BIGINT NOT NULL,
    visit_occurrence_id BIGINT,
    charttime TIMESTAMP NOT NULL,
    
    -- SOFA component scores (0-4 each)
    resp_score INTEGER,
    cardio_score INTEGER,
    neuro_score INTEGER,
    renal_score INTEGER,
    hepatic_score INTEGER,
    coag_score INTEGER,
    total_sofa INTEGER,
    
    -- Respiratory provenance (FIX #2, #3: no imputation, 240min window)
    pao2_value NUMERIC,
    fio2_value NUMERIC,
    pf_ratio NUMERIC,
    fio2_delta_minutes INTEGER,
    fio2_imputed BOOLEAN DEFAULT FALSE,
    fio2_source_table TEXT,
    vent_status BOOLEAN,
    vent_source TEXT,
    
    -- Cardiovascular provenance (FIX #1, #8: vasopressin included, units normalized)
    nee_total NUMERIC,
    norepinephrine_dose NUMERIC,
    epinephrine_dose NUMERIC,
    vasopressin_dose NUMERIC,
    vasopressin_included BOOLEAN DEFAULT TRUE,
    phenylephrine_dose NUMERIC,
    dopamine_dose NUMERIC,
    map_value NUMERIC,
    
    -- Neurological provenance (FIX #4: no forced verbal=1, RASS nulling)
    gcs_total INTEGER,
    gcs_eye INTEGER,
    gcs_motor INTEGER,
    gcs_verbal INTEGER,
    gcs_method TEXT, -- 'measured', 'sedated_null', 'preintubation_carry'
    rass_score INTEGER,
    intubated BOOLEAN,
    
    -- Renal provenance (FIX #6: 24h urine, RRT)
    creatinine_value NUMERIC,
    urine_output_24h_ml NUMERIC,
    rrt_active BOOLEAN,
    rrt_type TEXT,
    
    -- Hepatic & Coagulation
    bilirubin_value NUMERIC,
    platelets_value NUMERIC,
    
    -- Baseline (FIX #5: pre-infection, not last_available)
    baseline_sofa INTEGER,
    baseline_method TEXT DEFAULT 'pre_infection_72h',
    infection_onset TIMESTAMP,
    
    -- Metadata
    code_version TEXT DEFAULT 'v4.4-COMPLETE',
    calculation_time TIMESTAMP DEFAULT NOW(),
    
    PRIMARY KEY (person_id, charttime)
);

CREATE INDEX idx_assumptions_person ON results.sofa_assumptions(person_id);
CREATE INDEX idx_assumptions_time ON results.sofa_assumptions(charttime);
CREATE INDEX idx_assumptions_visit ON results.sofa_assumptions(visit_occurrence_id);

COMMENT ON TABLE results.sofa_assumptions IS 'Full audit trail for SOFA calculations - all imputations logged';

SELECT 'Assumptions table created with 32 fields (was 15 in v3.5)' AS status;
