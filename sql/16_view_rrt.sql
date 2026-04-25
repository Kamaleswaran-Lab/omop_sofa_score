-- Renal replacement therapy
CREATE OR REPLACE VIEW :results_schema.view_rrt AS
SELECT DISTINCT person_id, procedure_datetime AS rrt_time
FROM :cdm_schema.procedure_occurrence
WHERE procedure_concept_id IN (4146536, 4141984); -- dialysis concepts
