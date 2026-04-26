-- FIXED: using validated blood culture specimen IDs from Athena
-- 618898,1447635,3516065,3667301,3667306
CREATE OR REPLACE VIEW :results_schema.view_cultures AS
SELECT s.person_id, s.specimen_datetime
FROM :cdm_schema.specimen s
WHERE s.specimen_concept_id IN (618898,1447635,3516065,3667301,3667306);