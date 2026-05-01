-- 40_create_sepsis3_enhanced.sql
-- MGH version 2026-05-01 - CORRECTED
-- Optimized for 425M rows, with proper SOFA scoring (0-24, NOT capped at 4)

DROP TABLE IF EXISTS :results_schema.sepsis3_windows CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3_cohort CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3 CASCADE;

-- Performance settings
SET work_mem = '8GB';
SET max_parallel_workers_per_gather = 4;
SET enable_nestloop = on;
SET synchronous_commit = off;

-- 1) Build infection windows
CREATE UNLOGGED TABLE :results_schema.sepsis3_windows AS
SELECT
  io.person_id,
  io.infection_onset,
  io.infection_onset - INTERVAL '24 hours' AS baseline_start,
  io.infection_onset - INTERVAL '48 hours' AS window_start,
  io.infection_onset + INTERVAL '24 hours' AS window_end,
  io.antibiotic_time,
  io.culture_time
FROM :results_schema.view_infection_onset io;

CREATE INDEX idx_sepsis3_windows_pid ON :results_schema.sepsis3_windows (person_id);
CLUSTER :results_schema.sepsis3_windows USING idx_sepsis3_windows_pid;
ANALYZE :results_schema.sepsis3_windows;

-- 2) Filter time windows first, THEN score SOFA
CREATE UNLOGGED TABLE :results_schema.sepsis3_enhanced AS
WITH time_filtered_sofa AS (
  SELECT 
    w.person_id,
    w.infection_onset,
    w.baseline_start,
    w.window_start,
    w.window_end,
    w.antibiotic_time,
    w.culture_time,
    sh.hr,
    sh.pf_ratio,
    sh.platelets,
    sh.bilirubin,
    sh.map,
    sh.gcs_total,
    sh.rrt_active,
    sh.urine_24h_ml,
    sh.creatinine
  FROM :results_schema.sepsis3_windows w
  JOIN :results_schema.sofa_hourly sh
    ON sh.person_id = w.person_id
   AND sh.hr BETWEEN w.window_start AND w.window_end
),
sofa_scored AS (
  SELECT
    person_id,
    infection_onset,
    baseline_start,
    window_start,
    window_end,
    antibiotic_time,
    culture_time,
    hr,
    -- CORRECTED: Sum of 6 systems, each 0-4, total 0-24 (NO outer LEAST/GREATEST)
    (
      CASE WHEN pf_ratio IS NULL THEN 0 WHEN pf_ratio >= 400 THEN 0 WHEN pf_ratio >= 300 THEN 1 WHEN pf_ratio >= 200 THEN 2 WHEN pf_ratio >= 100 THEN 3 ELSE 4 END +
      CASE WHEN platelets IS NULL THEN 0 WHEN platelets > 150 THEN 0 WHEN platelets > 100 THEN 1 WHEN platelets > 50 THEN 2 WHEN platelets > 20 THEN 3 ELSE 4 END +
      CASE WHEN bilirubin IS NULL THEN 0 WHEN bilirubin/17.1 < 1.2 THEN 0 WHEN bilirubin/17.1 <= 1.9 THEN 1 WHEN bilirubin/17.1 <= 5.9 THEN 2 WHEN bilirubin/17.1 <= 11.9 THEN 3 ELSE 4 END +
      CASE WHEN map IS NULL THEN 0 WHEN map >= 70 THEN 0 ELSE 1 END +
      CASE WHEN gcs_total IS NULL THEN 0 WHEN gcs_total >= 15 THEN 0 WHEN gcs_total >= 13 THEN 1 WHEN gcs_total >= 10 THEN 2 WHEN gcs_total >= 6 THEN 3 ELSE 4 END +
      CASE WHEN rrt_active THEN 4 WHEN urine_24h_ml IS NOT NULL AND urine_24h_ml < 200 THEN 4 WHEN urine_24h_ml IS NOT NULL AND urine_24h_ml < 500 THEN 3 WHEN creatinine IS NULL THEN 0 WHEN creatinine/88.4 < 1.2 THEN 0 WHEN creatinine/88.4 <= 1.9 THEN 1 WHEN creatinine/88.4 <= 3.4 THEN 2 WHEN creatinine/88.4 <= 4.9 THEN 3 ELSE 4 END
    ) AS sofa_total
  FROM time_filtered_sofa
)
SELECT
  person_id,
  infection_onset,
  baseline_start,
  window_end,
  antibiotic_time,
  culture_time,
  COALESCE(MIN(sofa_total) FILTER (WHERE hr BETWEEN baseline_start AND infection_onset), 0) AS baseline_sofa,
  COALESCE(MAX(sofa_total), 0) AS max_sofa,
  COALESCE(MAX(sofa_total), 0) - COALESCE(MIN(sofa_total) FILTER (WHERE hr BETWEEN baseline_start AND infection_onset), 0) AS sofa_delta
FROM sofa_scored
GROUP BY person_id, infection_onset, baseline_start, window_start, window_end, antibiotic_time, culture_time;

ALTER TABLE :results_schema.sepsis3_enhanced SET LOGGED;
CREATE INDEX idx_sepsis3_enhanced_pid_onset ON :results_schema.sepsis3_enhanced (person_id, infection_onset);
ANALYZE :results_schema.sepsis3_enhanced;

-- 3) Sepsis-3 cohort
CREATE TABLE :results_schema.sepsis3_cohort AS
SELECT * FROM :results_schema.sepsis3_enhanced WHERE sofa_delta >= 2;

CREATE INDEX idx_sepsis3_cohort_pid_onset ON :results_schema.sepsis3_cohort (person_id, infection_onset);

-- 4) Compatibility
CREATE TABLE :results_schema.sepsis3 AS SELECT * FROM :results_schema.sepsis3_cohort;

ANALYZE :results_schema.sepsis3_cohort;
ANALYZE :results_schema.sepsis3;

-- validation
SELECT 'windows' AS tbl, COUNT(*) FROM :results_schema.sepsis3_windows
UNION ALL SELECT 'enhanced', COUNT(*) FROM :results_schema.sepsis3_enhanced
UNION ALL SELECT 'cohort_delta_ge2', COUNT(*) FROM :results_schema.sepsis3_cohort;
