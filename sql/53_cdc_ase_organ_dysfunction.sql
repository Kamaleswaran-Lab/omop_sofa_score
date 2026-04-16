-- 53_cdc_ase_organ_dysfunction.sql
-- PURPOSE: Identify organ dysfunction within ±2 days of culture
-- FIXES: use timestamps, include vasopressors and ventilation from corrected views

DROP TABLE IF EXISTS omop_cdm.ase_organ_dysfunction CASCADE;
CREATE TABLE omop_cdm.ase_organ_dysfunction AS
WITH params AS (SELECT * FROM omop_sofa.ase_parameters)
SELECT
  bc.person_id,
  bc.visit_occurrence_id,
  bc.culture_datetime,
  -- vasopressor initiation
  EXISTS (
    SELECT 1 FROM omop_sofa.vasopressors_nee v
    WHERE v.person_id = bc.person_id
      AND v.start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days'
                               AND bc.culture_datetime + INTERVAL '2 days'
  ) AS vaso_init,
  -- ventilation initiation
  EXISTS (
    SELECT 1 FROM omop_sofa.ventilation vent
    WHERE vent.person_id = bc.person_id
      AND vent.start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days'
                                  AND bc.culture_datetime + INTERVAL '2 days'
  ) AS vent_init,
  -- lactate >=2 mmol/L
  EXISTS (
    SELECT 1 FROM omop_cdm.measurement m
    WHERE m.person_id = bc.person_id
      AND m.measurement_concept_id = 3024128 -- lactate
      AND m.value_as_number >= 2.0
      AND m.measurement_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days'
                                     AND bc.culture_datetime + INTERVAL '2 days'
  ) AS lactate_high
FROM omop_cdm.ase_blood_cultures bc
CROSS JOIN params
;
