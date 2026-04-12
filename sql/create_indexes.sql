CREATE INDEX idx_meas_pt ON cdm.measurement(person_id, measurement_datetime);
CREATE INDEX idx_drug_pt ON cdm.drug_exposure(person_id, drug_exposure_start_datetime);
CREATE INDEX idx_device_pt ON cdm.device_exposure(person_id, device_exposure_start_datetime);
CREATE INDEX idx_proc_pt ON cdm.procedure_occurrence(person_id, procedure_datetime);