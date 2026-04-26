-- Performance indexes for OMOP CDM
-- Use with -v cdm_schema=...

CREATE INDEX IF NOT EXISTS idx_measurement_person_time 
ON :cdm_schema.measurement (person_id, measurement_datetime);

CREATE INDEX IF NOT EXISTS idx_measurement_concept 
ON :cdm_schema.measurement (measurement_concept_id);

CREATE INDEX IF NOT EXISTS idx_measurement_concept_time 
ON :cdm_schema.measurement (measurement_concept_id, measurement_datetime);

CREATE INDEX IF NOT EXISTS idx_drug_person_time 
ON :cdm_schema.drug_exposure (person_id, drug_exposure_start_datetime);

CREATE INDEX IF NOT EXISTS idx_drug_concept_time
ON :cdm_schema.drug_exposure (drug_concept_id, drug_exposure_start_datetime);

CREATE INDEX IF NOT EXISTS idx_procedure_person_time 
ON :cdm_schema.procedure_occurrence (person_id, procedure_datetime);

CREATE INDEX IF NOT EXISTS idx_procedure_concept_time
ON :cdm_schema.procedure_occurrence (procedure_concept_id, procedure_datetime);

CREATE INDEX IF NOT EXISTS idx_specimen_person_time 
ON :cdm_schema.specimen (person_id, specimen_datetime);

CREATE INDEX IF NOT EXISTS idx_device_person_time
ON :cdm_schema.device_exposure (person_id, device_exposure_start_datetime);

CREATE INDEX IF NOT EXISTS idx_visit_person_time
ON :cdm_schema.visit_occurrence (person_id, visit_start_datetime);
