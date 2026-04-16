-- 13_view_ventilation.sql
-- PURPOSE: Identify initiation of invasive mechanical ventilation
-- FIXES vs original:
--  1) Include device_exposure (most OMOP sites store ventilator here)
--  2) Include procedure_occurrence for intubation
--  3) Drive concept lists from assumptions (domain='ventilation')
--  4) Do not require end time

DROP VIEW IF EXISTS omop_sofa.ventilation CASCADE;
CREATE OR REPLACE VIEW omop_sofa.ventilation AS
WITH vent_concepts AS (
  SELECT concept_id FROM omop_sofa.assumptions WHERE domain = 'ventilation'
)
-- procedures (intubation, initiation)
SELECT
  po.person_id,
  po.visit_occurrence_id,
  COALESCE(po.procedure_datetime, po.procedure_date::timestamp) AS start_datetime,
  'procedure' AS source_domain
FROM omop_cdm.procedure_occurrence po
JOIN vent_concepts vc ON vc.concept_id = po.procedure_concept_id

UNION ALL

-- devices (ventilator)
SELECT
  de.person_id,
  de.visit_occurrence_id,
  COALESCE(de.device_exposure_start_datetime, de.device_exposure_start_date::timestamp) AS start_datetime,
  'device' AS source_domain
FROM omop_cdm.device_exposure de
JOIN vent_concepts vc ON vc.concept_id = de.device_concept_id
;

COMMENT ON VIEW omop_sofa.ventilation IS 'Ventilation initiation from procedures + devices; site-tolerant';
