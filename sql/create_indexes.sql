-- sql/create_indexes.sql
-- Required indexes for performance on large OMOP instances

CREATE INDEX IF NOT EXISTS idx_measurement_person_concept_time 
ON omopcdm.measurement (person_id, measurement_concept_id, COALESCE(measurement_datetime, measurement_date));

CREATE INDEX IF NOT EXISTS idx_drug_person_concept_route 
ON omopcdm.drug_exposure (person_id, drug_concept_id, route_concept_id);

CREATE INDEX IF NOT EXISTS idx_procedure_person_concept 
ON omopcdm.procedure_occurrence (person_id, procedure_concept_id, COALESCE(procedure_datetime, procedure_date));

CREATE INDEX IF NOT EXISTS idx_specimen_person_concept 
ON omopcdm.specimen (person_id, specimen_concept_id, COALESCE(specimen_datetime, specimen_date));

CREATE INDEX IF NOT EXISTS idx_condition_person 
ON omopcdm.condition_occurrence (person_id, condition_concept_id);
