-- OMOP SOFA v4.4 - Renal replacement therapy
-- FIX #6: RRT detection forces renal SOFA = 4

DROP VIEW IF EXISTS results.v_rrt CASCADE;

CREATE VIEW results.v_rrt AS
SELECT DISTINCT
    po.person_id,
    po.procedure_datetime AS rrt_start,
    COALESCE(
        po.procedure_end_datetime, 
        po.procedure_datetime + INTERVAL '4 hours'
    ) AS rrt_end,
    po.procedure_concept_id,
    c.concept_name AS rrt_type,
    'dialysis' AS rrt_category
FROM cdm.procedure_occurrence po
JOIN vocab.concept c ON c.concept_id = po.procedure_concept_id
WHERE po.procedure_concept_id IN (
    SELECT descendant_concept_id 
    FROM vocab.concept_ancestor 
    WHERE ancestor_concept_id = 4146536  -- Dialysis procedures
)
AND po.procedure_datetime IS NOT NULL;

COMMENT ON VIEW results.v_rrt IS 'RRT detection - forces renal SOFA 4';

SELECT 'RRT view created (FIX #6)' AS status;
