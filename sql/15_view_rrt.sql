
-- RRT detection forces renal=4
CREATE OR REPLACE VIEW results.v_rrt AS
SELECT person_id, procedure_datetime AS dt, TRUE AS rrt
FROM cdm.procedure_occurrence WHERE procedure_concept_id IN (SELECT descendant_concept_id FROM vocab.concept_ancestor WHERE ancestor_concept_id=4146536);
