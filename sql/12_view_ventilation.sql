
-- FIX 9: multi-domain ventilation detection
CREATE OR REPLACE VIEW results.v_ventilation AS
SELECT person_id, device_exposure_start_datetime AS start_dt, device_exposure_end_datetime AS end_dt, 'device' AS src
FROM cdm.device_exposure WHERE device_concept_id IN (SELECT descendant_concept_id FROM vocab.concept_ancestor WHERE ancestor_concept_id=45768131)
UNION ALL
SELECT person_id, procedure_datetime AS start_dt, procedure_datetime + interval '1 hour' AS end_dt, 'procedure' AS src
FROM cdm.procedure_occurrence WHERE procedure_concept_id IN (SELECT descendant_concept_id FROM vocab.concept_ancestor WHERE ancestor_concept_id=4302207);
