CREATE INDEX IF NOT EXISTS idx_de_person_time ON :cdm_schema.drug_exposure (person_id, drug_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_meas_person_time ON :cdm_schema.measurement (person_id, measurement_datetime);
CREATE INDEX IF NOT EXISTS idx_de_concept_person_time ON :cdm_schema.drug_exposure (drug_concept_id, person_id, drug_exposure_start_datetime);
CREATE INDEX IF NOT EXISTS idx_meas_concept_person_time ON :cdm_schema.measurement (measurement_concept_id, person_id, measurement_datetime);
CREATE INDEX IF NOT EXISTS idx_obs_concept_person_time ON :cdm_schema.observation (observation_concept_id, person_id, observation_datetime);
CREATE INDEX IF NOT EXISTS idx_proc_concept_person_time ON :cdm_schema.procedure_occurrence (procedure_concept_id, person_id, procedure_datetime);
CREATE INDEX IF NOT EXISTS idx_specimen_concept_person_time ON :cdm_schema.specimen (specimen_concept_id, person_id, specimen_datetime);
CREATE INDEX IF NOT EXISTS idx_visit_person_start_end ON :cdm_schema.visit_occurrence (person_id, visit_start_datetime, visit_end_datetime);
CREATE INDEX IF NOT EXISTS idx_visit_detail_visit_time ON :cdm_schema.visit_detail (visit_occurrence_id, visit_detail_start_datetime, visit_detail_end_datetime);
