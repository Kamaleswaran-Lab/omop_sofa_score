-- 41_create_sepsis3_collapsed_48h.sql
-- Site A: 48h collapse (configurable)

DROP TABLE IF EXISTS {{results_schema}}.sepsis3_enhanced_collapsed CASCADE;
CREATE TABLE {{results_schema}}.sepsis3_enhanced_collapsed AS
WITH ordered AS (
  SELECT *,
    LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) AS prev_onset
  FROM {{results_schema}}.sepsis3_enhanced
  WHERE meets_sepsis3
),
groups AS (
  SELECT *,
    SUM(CASE WHEN prev_onset IS NULL OR infection_onset - prev_onset > interval '48 hours' THEN 1 ELSE 0 END)
      OVER (PARTITION BY person_id ORDER BY infection_onset) AS episode_group
  FROM ordered
)
SELECT
  person_id,
  MIN(visit_occurrence_id) AS visit_occurrence_id,
  MIN(infection_onset) AS infection_onset,
  MAX(delta_sofa) AS max_delta_sofa,
  COUNT(*) AS n_collapsed_events
FROM groups
GROUP BY person_id, episode_group;
