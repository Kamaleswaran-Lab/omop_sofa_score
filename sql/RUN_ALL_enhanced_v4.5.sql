-- FIXED: removed 40484543,40486635,2072499989; removed WHERE icu_onset=1
\set ON_ERROR_STOP on
SELECT * FROM :cdm_schema.visit_detail WHERE visit_detail_concept_id IN (32037,581379); -- portable ICU, no B2AI
-- No icu_onset filter for full inpatient trajectories
