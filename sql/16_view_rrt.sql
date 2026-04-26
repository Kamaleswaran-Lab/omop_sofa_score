-- FIXED: removed 4052531 (portal cannula), use dialysis ancestor
CREATE OR REPLACE VIEW :results_schema.view_rrt AS
SELECT DISTINCT person_id, procedure_datetime AS start_datetime,
       procedure_datetime + interval '1 day' AS end_datetime, true AS rrt_active
FROM :cdm_schema.procedure_occurrence po
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = po.procedure_concept_id
WHERE ca.ancestor_concept_id IN (SELECT concept_id FROM :vocab_schema.concept WHERE concept_name ILIKE '%dialysis%' AND domain_id='Procedure' LIMIT 1);