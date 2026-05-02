-- 53_cdc_ase_organ_dysfunction.sql
-- CDC ASE organ dysfunction flags using canonical concept sets.

DROP TABLE IF EXISTS :results_schema.ase_organ_dysfunction CASCADE;
CREATE TABLE :results_schema.ase_organ_dysfunction AS
SELECT
  bc.person_id,
  bc.culture_datetime,

  -- 1. Vasopressors (±2 days) – name-based to avoid missing MGH mappings
  EXISTS (
    SELECT 1
    FROM :results_schema.view_vasopressors_nee de
    WHERE de.person_id = bc.person_id
      AND de.start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days'
                                AND bc.culture_datetime + INTERVAL '2 days'
  ) AS vaso_init,

  -- 2. Ventilation (±2 days) – INTUBATION ONLY
  EXISTS (
    SELECT 1
    FROM :results_schema.view_ventilation vent
    WHERE vent.person_id = bc.person_id
      AND vent.start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days'
                                  AND bc.culture_datetime + INTERVAL '2 days'
  ) AS vent_init,

  -- 3. Lactate >=2.0 (±2 days)
  EXISTS (
    SELECT 1
    FROM :cdm_schema.measurement m
    WHERE m.person_id = bc.person_id
      AND m.measurement_concept_id IN (
        SELECT concept_id FROM :results_schema.concept_set_members WHERE concept_set_name = 'lactate'
      )
      AND m.value_as_number >= 2.0
      AND COALESCE(m.measurement_datetime, m.measurement_date::timestamp)
          BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
  ) AS lactate_high

FROM :results_schema.cdc_ase_cultures bc;
