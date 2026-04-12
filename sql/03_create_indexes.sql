
CREATE INDEX IF NOT EXISTS idx_meas_person_time ON cdm.measurement(person_id, measurement_datetime);
CREATE INDEX IF NOT EXISTS idx_drug_person_time ON cdm.drug_exposure(person_id, drug_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_device_person_time ON cdm.device_exposure(person_id, device_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_proc_person_time ON cdm.procedure_occurrence(person_id, procedure_datetime);
CREATE INDEX IF NOT EXISTS idx_obs_person_time ON cdm.observation(person_id, observation_datetime);
