CREATE INDEX IF NOT EXISTS idx_measurement_person_time ON omopcdm.measurement (person_id, measurement_datetime);
CREATE INDEX IF NOT EXISTS idx_measurement_concept ON omopcdm.measurement (measurement_concept_id);
CREATE INDEX IF NOT EXISTS idx_drug_person_time ON omopcdm.drug_exposure (person_id, drug_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_drug_concept ON omopcdm.drug_exposure (drug_concept_id);