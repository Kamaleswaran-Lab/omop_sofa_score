-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_de_person_time ON :cdm_schema.drug_exposure (person_id, drug_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_meas_person_time ON :cdm_schema.measurement (person_id, measurement_datetime);
CREATE INDEX IF NOT EXISTS idx_spec_person_time ON :cdm_schema.specimen (person_id, specimen_datetime);
CREATE INDEX IF NOT EXISTS idx_visit_detail_person ON :cdm_schema.visit_detail (person_id, visit_detail_start_datetime);
