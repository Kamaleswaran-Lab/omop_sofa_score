
CREATE TABLE IF NOT EXISTS results.sofa_assumptions (
  person_id BIGINT, visit_occurrence_id BIGINT, charttime TIMESTAMP,
  component VARCHAR(20), score INTEGER, value_raw NUMERIC, concept_id INTEGER,
  source_table VARCHAR(50), measurement_datetime TIMESTAMP,
  pao2_value NUMERIC, fio2_value NUMERIC, fio2_delta_min INTEGER,
  fio2_imputed BOOLEAN DEFAULT FALSE, fio2_source VARCHAR(50),
  vasopressor_nee NUMERIC, vasopressin_dose NUMERIC, vasopressin_included BOOLEAN DEFAULT TRUE,
  norepi_dose NUMERIC, epi_dose NUMERIC,
  gcs_total INTEGER, gcs_method VARCHAR(50), rass_value INTEGER,
  urine_24h_ml NUMERIC, creatinine_value NUMERIC,
  rrt_flag BOOLEAN, vent_detected BOOLEAN, vent_source VARCHAR(50),
  platelets_value NUMERIC, bilirubin_value NUMERIC,
  baseline_sofa INTEGER, baseline_method VARCHAR(50),
  infection_onset TIMESTAMP, window_used_min INTEGER,
  code_version VARCHAR(20) DEFAULT 'v4.1',
  created_at TIMESTAMP DEFAULT NOW()
);