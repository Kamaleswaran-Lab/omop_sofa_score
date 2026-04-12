
CREATE OR REPLACE VIEW results.v_cultures AS
SELECT m.person_id, m.measurement_datetime AS cx_time
FROM cdm.measurement m
WHERE m.measurement_concept_id IN (SELECT descendant_concept_id FROM vocab.concept_ancestor WHERE ancestor_concept_id=4046263); -- microbiology
