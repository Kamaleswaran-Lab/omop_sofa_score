-- 40_create_sepsis3_enhanced.sql
-- Site A edit: baseline SOFA window 72h (not 24h), reduces imputation
-- v4.5 enhanced

DROP TABLE IF EXISTS {{results_schema}}.sepsis3_enhanced CASCADE;
CREATE TABLE {{results_schema}}.sepsis3_enhanced AS
WITH io AS (
  SELECT * FROM {{results_schema}}.view_infection_onset_enhanced
),
baseline AS (
  SELECT
    io.person_id,
    io.visit_occurrence_id,
    io.infection_onset,
    -- SITE A CHANGE: use 72h lookback for baseline
    COALESCE(
      MIN(sh.total_sofa) FILTER (WHERE sh.charttime BETWEEN io.infection_onset - interval '72 hours' AND io.infection_onset - interval '1 hour'),
      0
    ) AS baseline_sofa,
    COUNT(*) FILTER (WHERE sh.charttime BETWEEN io.infection_onset - interval '24 hours' AND io.infection_onset) AS n_baseline_24h,
    COUNT(*) FILTER (WHERE sh.charttime BETWEEN io.infection_onset - interval '48 hours' AND io.infection_onset) AS n_baseline_48h,
    (MIN(sh.total_sofa) FILTER (WHERE sh.charttime BETWEEN io.infection_onset - interval '72 hours' AND io.infection_onset) IS NULL) AS baseline_imputed
  FROM io
  LEFT JOIN {{results_schema}}.sofa_hourly sh
    ON sh.person_id = io.person_id
   AND sh.charttime BETWEEN io.infection_onset - interval '72 hours' AND io.infection_onset + interval '72 hours'
  GROUP BY 1,2,3
),
peak AS (
  SELECT
    io.person_id,
    io.visit_occurrence_id,
    io.infection_onset,
    MAX(sh.total_sofa) FILTER (WHERE sh.charttime BETWEEN io.infection_onset AND io.infection_onset + interval '72 hours') AS peak_sofa
  FROM io
  JOIN {{results_schema}}.sofa_hourly sh
    ON sh.person_id = io.person_id
   AND sh.charttime BETWEEN io.infection_onset AND io.infection_onset + interval '72 hours'
  GROUP BY 1,2,3
)
SELECT
  b.person_id,
  b.visit_occurrence_id,
  io.infection_onset,
  io.infection_type,
  io.antibiotic_start,
  io.culture_start,
  io.culture_site,
  b.baseline_sofa,
  p.peak_sofa,
  (p.peak_sofa - b.baseline_sofa) AS delta_sofa,
  b.n_baseline_24h,
  b.n_baseline_48h,
  b.baseline_imputed,
  (p.peak_sofa - b.baseline_sofa) >= 2 AS meets_sepsis3
FROM baseline b
JOIN peak p USING (person_id, visit_occurrence_id, infection_onset)
JOIN io USING (person_id, visit_occurrence_id, infection_onset);

CREATE INDEX ON {{results_schema}}.sepsis3_enhanced (person_id, visit_occurrence_id);
