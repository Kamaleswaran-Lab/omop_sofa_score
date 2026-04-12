-- OMOP SOFA v4.4 - Performance indexes
-- Critical for large OMOP instances (MIMIC-IV, N3C)

-- Measurement table (labs)
CREATE INDEX IF NOT EXISTS idx_measurement_person_time 
    ON cdm.measurement(person_id, measurement_datetime);
CREATE INDEX IF NOT EXISTS idx_measurement_concept 
    ON cdm.measurement(measurement_concept_id);
CREATE INDEX IF NOT EXISTS idx_measurement_person_concept 
    ON cdm.measurement(person_id, measurement_concept_id, measurement_datetime);

-- Drug exposure (vasopressors, antibiotics)
CREATE INDEX IF NOT EXISTS idx_drug_person_time 
    ON cdm.drug_exposure(person_id, drug_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_drug_concept 
    ON cdm.drug_exposure(drug_concept_id);

-- Device exposure (ventilation)
CREATE INDEX IF NOT EXISTS idx_device_person_time 
    ON cdm.device_exposure(person_id, device_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_device_concept 
    ON cdm.device_exposure(device_concept_id);

-- Procedures (RRT, ventilation, cultures)
CREATE INDEX IF NOT EXISTS idx_procedure_person_time 
    ON cdm.procedure_occurrence(person_id, procedure_datetime);
CREATE INDEX IF NOT EXISTS idx_procedure_concept 
    ON cdm.procedure_occurrence(procedure_concept_id);

-- Observations (GCS, RASS)
CREATE INDEX IF NOT EXISTS idx_observation_person_time 
    ON cdm.observation(person_id, observation_datetime);
CREATE INDEX IF NOT EXISTS idx_observation_concept 
    ON cdm.observation(observation_concept_id);

-- Visits
CREATE INDEX IF NOT EXISTS idx_visit_person 
    ON cdm.visit_occurrence(person_id, visit_start_datetime);
CREATE INDEX IF NOT EXISTS idx_visit_concept 
    ON cdm.visit_occurrence(visit_concept_id);

SELECT 'All performance indexes created' AS status;
