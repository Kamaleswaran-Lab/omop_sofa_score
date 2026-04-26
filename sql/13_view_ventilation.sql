CREATE OR REPLACE VIEW :results_schema.view_ventilation AS
SELECT person_id, procedure_datetime AS start_time FROM :cdm_schema.procedure_occurrence WHERE procedure_concept_id IN (4065110,4145896);