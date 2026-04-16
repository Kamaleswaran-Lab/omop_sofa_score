DROP TABLE IF EXISTS :results_schema.ase_blood_cultures CASCADE;
CREATE TABLE :results_schema.ase_blood_cultures AS
SELECT
  person_id,
  visit_occurrence_id,
  COALESCE(measurement_datetime, measurement_date::timestamp) AS culture_datetime,
  measurement_concept_id
FROM :cdm_schema.measurement m
WHERE m.measurement_concept_id IN (
  3023368,  -- Bacteria identified in Blood by Culture (45k rows)
  3015479,  -- Mycobacterium sp identified in Blood by Organism specific culture
  3009171,  -- Fungus identified in Blood by Culture
  3053320,  -- Bacteria #2 identified in Blood by Culture
  36203568, 36204426, 36031504, 36031871, 36032118, 36032205, 36032369, 36032325, 36203226, 36031851 -- DNA positives
)
AND measurement_datetime IS NOT NULL;

CREATE INDEX idx_ase_bc_person ON :results_schema.ase_blood_cultures(person_id, culture_datetime);
CREATE INDEX idx_ase_bc_visit ON :results_schema.ase_blood_cultures(visit_occurrence_id);
