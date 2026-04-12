-- sql/create_assumptions_table.sql
-- Audit trail for all pragmatic imputations - required for TTE sensitivity analysis

CREATE TABLE IF NOT EXISTS sofa_assumptions (
    person_id BIGINT NOT NULL,
    visit_occurrence_id BIGINT NOT NULL,
    charttime TIMESTAMP NOT NULL,
    -- Oxygenation
    fio2_imputed BOOLEAN DEFAULT FALSE,
    fio2_imputation_method TEXT, -- 'none', 'vent_carryforward', 'vent_assumed_60', 'room_air_21'
    pf_source TEXT, -- 'pao2_fio2', 'spo2_fio2', 'imputed'
    -- Vasopressors
    vaso_present BOOLEAN DEFAULT FALSE,
    vaso_rate_derived BOOLEAN DEFAULT FALSE,
    vaso_rate_source TEXT, -- 'direct', 'weight_adjusted', 'quantity_duration_weight', 'quantity_duration_70kg', 'unknown'
    vaso_assumed_weight BOOLEAN DEFAULT FALSE,
    -- Concepts
    bilirubin_source TEXT, -- 'ancestor', 'hardcoded', 'both'
    creatinine_source TEXT,
    platelets_source TEXT,
    -- Baseline
    baseline_sofa NUMERIC,
    baseline_imputed BOOLEAN DEFAULT FALSE,
    baseline_source TEXT, -- 'min_72_6', 'last_24_1', 'imputed_zero', 'chronic_disease'
    -- General
    pragmatic_mode BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (person_id, visit_occurrence_id, charttime)
);

CREATE INDEX idx_sofa_assumptions_person ON sofa_assumptions(person_id, charttime);
CREATE INDEX idx_sofa_assumptions_imputed ON sofa_assumptions(fio2_imputed, baseline_imputed);

COMMENT ON TABLE sofa_assumptions IS 'Audit log for all imputations in pragmatic SOFA calculation. Required for target trial emulation sensitivity analyses.';
