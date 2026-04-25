-- Renal replacement therapy - expanded concepts with duration
DROP VIEW IF EXISTS :results_schema.vw_rrt CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_rrt AS
WITH rrt_concepts AS (
  SELECT descendant_concept_id AS concept_id
  FROM :vocab_schema.concept_ancestor
  WHERE ancestor_concept_id = 4052531  -- Renal dialysis
  UNION
  SELECT 4197217 UNION SELECT 2109463  -- your originals
)
SELECT DISTINCT 
    po.person_id, 
    po.visit_occurrence_id,
    COALESCE(po.procedure_datetime, po.procedure_date::timestamp) AS start_datetime,
    COALESCE(po.procedure_end_datetime, 
             COALESCE(po.procedure_datetime, po.procedure_date::timestamp) + INTERVAL '24 hours') AS end_datetime,
    TRUE AS rrt_active,
    po.procedure_concept_id
FROM :cdm_schema.procedure_occurrence po
JOIN rrt_concepts rc ON rc.concept_id = po.procedure_concept_id;
