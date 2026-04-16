-- 51_cdc_ase_blood_cultures.sql
DROP TABLE IF EXISTS :results_schema.ase_blood_cultures CASCADE;
CREATE TABLE :results_schema.ase_blood_cultures AS
SELECT m.person_id, m.visit_occurrence_id,
       COALESCE(m.measurement_datetime, m.measurement_date::timestamp) AS culture_datetime
FROM :cdm_schema.measurement m
JOIN :results_schema.assumptions a ON a.domain='blood_culture' AND a.concept_id = m.measurement_concept_id;
CREATE INDEX idx_ase_bc ON :results_schema.ase_blood_cultures(person_id, culture_datetime);
