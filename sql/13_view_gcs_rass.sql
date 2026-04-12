
-- FIX 4: GCS with RASS, no forced verbal=1
CREATE OR REPLACE VIEW results.v_neuro AS
SELECT o.person_id, o.observation_datetime AS dt,
       MAX(CASE WHEN o.observation_concept_id IN (SELECT descendant_concept_id FROM vocab.concept_ancestor WHERE ancestor_concept_id=4253928) THEN o.value_as_number END) AS gcs,
       MAX(CASE WHEN o.observation_concept_id IN (SELECT descendant_concept_id FROM vocab.concept_ancestor WHERE ancestor_concept_id=40488434) THEN o.value_as_number END) AS rass
FROM cdm.observation o
GROUP BY 1,2;
