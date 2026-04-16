-- 53_cdc_ase_organ_dysfunction.sql
-- FIX: use timestamps not dates
DROP TABLE IF EXISTS :results_schema.ase_organ_dysfunction CASCADE;
CREATE TABLE :results_schema.ase_organ_dysfunction AS
SELECT bc.person_id, bc.visit_occurrence_id, bc.culture_datetime,
  EXISTS (SELECT 1 FROM :results_schema.vasopressors_nee v
          WHERE v.person_id=bc.person_id
            AND v.start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days') AS vaso_init,
  EXISTS (SELECT 1 FROM :results_schema.ventilation vent
          WHERE vent.person_id=bc.person_id
            AND vent.start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days') AS vent_init,
  EXISTS (SELECT 1 FROM :cdm_schema.measurement m
          WHERE m.person_id=bc.person_id AND m.measurement_concept_id=3024128 AND m.value_as_number>=2
            AND m.measurement_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days') AS lactate_high
FROM :results_schema.ase_blood_cultures bc;
