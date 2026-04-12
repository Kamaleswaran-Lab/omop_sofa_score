CREATE SCHEMA IF NOT EXISTS results;
CREATE TABLE results.sofa_assumptions (
 person_id BIGINT, visit_occurrence_id BIGINT, charttime TIMESTAMP,
 component VARCHAR(20), score INTEGER, value_raw NUMERIC, concept_id INTEGER,
 source_table VARCHAR(50), measurement_datetime TIMESTAMP,
 pao2_value NUMERIC, fio2_value NUMERIC, fio2_delta_min INTEGER,
 fio2_imputed BOOLEAN DEFAULT FALSE, fio2_source VARCHAR(50),
 vasopressor_nee NUMERIC, vasopressin_dose NUMERIC, vasopressin_included BOOLEAN,
 gcs_total INTEGER, gcs_method VARCHAR(50), rass_value INTEGER,
 urine_24h_ml NUMERIC, rrt_flag BOOLEAN, vent_detected BOOLEAN, vent_source VARCHAR(50),
 baseline_sofa INTEGER, baseline_method VARCHAR(50),
 window_used_min INTEGER, code_version VARCHAR(20) DEFAULT 'v4.0',
 created_at TIMESTAMP DEFAULT NOW()
);