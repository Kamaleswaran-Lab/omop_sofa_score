CREATE OR REPLACE VIEW results_site_a.vw_rrt AS
SELECT DISTINCT person_id, procedure_datetime AS charttime, TRUE AS rrt_active
FROM omopcdm.procedure_occurrence
WHERE procedure_concept_id IN (4197217, 2109463);