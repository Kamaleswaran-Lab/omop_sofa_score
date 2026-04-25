-- Mechanical ventilation from procedures and device_exposure
CREATE OR REPLACE VIEW :results_schema.view_ventilation AS
SELECT person_id, procedure_datetime AS start_time
FROM :cdm_schema.procedure_occurrence
WHERE procedure_concept_id IN (4065110, 4145896) -- intubation, invasive vent
UNION ALL
SELECT person_id, device_exposure_start_datetime
FROM :cdm_schema.device_exposure
WHERE device_concept_id = 45768192; -- ventilator
