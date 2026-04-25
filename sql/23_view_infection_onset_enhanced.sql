-- Pragmatic infection onset
CREATE OR REPLACE VIEW :results_schema.view_infection_onset_enhanced AS
WITH abx AS (
  SELECT person_id, drug_exposure_start_datetime AS abx_time, visit_occurrence_id
  FROM :cdm_schema.drug_exposure de
  JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
  WHERE ca.ancestor_concept_id IN (21602796,21602797)
),
cult AS (
  SELECT person_id, specimen_datetime AS cult_time
  FROM :cdm_schema.specimen
  WHERE specimen_concept_id IN (4048479,4051875)
),
pairs AS (
  SELECT a.person_id, LEAST(a.abx_time,c.cult_time) AS infection_onset
  FROM abx a JOIN cult c ON c.person_id=a.person_id
  WHERE ABS(EXTRACT(EPOCH FROM (a.abx_time-c.cult_time))/3600) <=96
),
multi AS (
  SELECT person_id, MIN(abx_time) AS infection_onset
  FROM (SELECT *, COUNT(*) OVER (PARTITION BY person_id ORDER BY abx_time RANGE BETWEEN INTERVAL '48 hours' PRECEDING AND CURRENT ROW) cnt FROM abx) t
  WHERE cnt>=2 GROUP BY person_id
),
icu AS (
  SELECT a.person_id, MIN(abx_time) AS infection_onset
  FROM abx a JOIN :cdm_schema.visit_detail vd ON vd.visit_detail_id=a.visit_occurrence_id
  WHERE vd.visit_detail_concept_id IN (32037,581379) GROUP BY 1
)
SELECT DISTINCT person_id, infection_onset FROM (
  SELECT * FROM pairs UNION ALL SELECT * FROM multi UNION ALL SELECT * FROM icu
) u WHERE infection_onset < CURRENT_DATE;
