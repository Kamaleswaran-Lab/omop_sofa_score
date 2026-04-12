
-- Core labs using ancestor concepts only
CREATE OR REPLACE VIEW results.v_lab AS
SELECT m.person_id, m.measurement_datetime AS dt, m.measurement_concept_id,
       m.value_as_number AS val, m.unit_concept_id,
       ca.ancestor_concept_id
FROM cdm.measurement m
JOIN vocab.concept_ancestor ca ON ca.descendant_concept_id = m.measurement_concept_id
WHERE ca.ancestor_concept_id IN (3002647,3013468,3016723,3024128,3013290,4065485); -- pao2,fio2,creat,bili,plt,urine
