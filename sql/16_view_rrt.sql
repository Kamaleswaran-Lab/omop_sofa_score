-- 16_view_rrt.sql
-- Renal replacement therapy windows from validated concept sets.

CREATE OR REPLACE VIEW :results_schema.view_rrt AS
SELECT DISTINCT
  po.person_id,
  COALESCE(po.procedure_datetime, po.procedure_date::timestamp) AS start_datetime,
  COALESCE(po.procedure_datetime, po.procedure_date::timestamp) + interval '1 day' AS end_datetime,
  true AS rrt_active
FROM :cdm_schema.procedure_occurrence po
JOIN :results_schema.concept_set_members cs
  ON cs.concept_id = po.procedure_concept_id
 AND cs.concept_set_name = 'rrt'
WHERE COALESCE(po.procedure_datetime, po.procedure_date::timestamp) IS NOT NULL;
