-- 51_cdc_ase_blood_cultures.sql
-- PURPOSE: Identify blood culture draws
-- FIX: use assumptions table, keep datetime

DROP TABLE IF EXISTS omop_cdm.ase_blood_cultures CASCADE;
CREATE TABLE omop_cdm.ase_blood_cultures AS
SELECT
  m.person_id,
  m.visit_occurrence_id,
  COALESCE(m.measurement_datetime, m.measurement_date::timestamp) AS culture_datetime,
  m.measurement_concept_id
FROM omop_cdm.measurement m
JOIN omop_sofa.assumptions a ON a.domain='blood_culture' AND a.concept_id = m.measurement_concept_id
WHERE m.value_as_concept_id IS NULL OR m.value_as_concept_id != 9189 -- exclude cancelled
;

CREATE INDEX idx_ase_bc_person ON omop_cdm.ase_blood_cultures(person_id, culture_datetime);
