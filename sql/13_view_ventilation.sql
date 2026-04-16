-- 13_view_ventilation.sql
-- FIX: include device_exposure

DROP VIEW IF EXISTS :results_schema.ventilation CASCADE;
CREATE OR REPLACE VIEW :results_schema.ventilation AS
WITH vent_concepts AS (
  SELECT concept_id FROM :results_schema.assumptions WHERE domain = 'ventilation'
)
SELECT po.person_id, po.visit_occurrence_id,
       COALESCE(po.procedure_datetime, po.procedure_date::timestamp) AS start_datetime
FROM :cdm_schema.procedure_occurrence po
JOIN vent_concepts vc ON vc.concept_id = po.procedure_concept_id
UNION ALL
SELECT de.person_id, de.visit_occurrence_id,
       COALESCE(de.device_exposure_start_datetime, de.device_exposure_start_date::timestamp)
FROM :cdm_schema.device_exposure de
JOIN vent_concepts vc ON vc.concept_id = de.device_concept_id;
