-- 40_create_sepsis3_enhanced.sql
-- MGH version 2026-05-01
-- Depends on: 31_create_sofa_hourly.sql (sofa_hourly must exist with map + gcs_total)
-- Changes: unit conversions for bilirubin (/17.1) and creatinine (/88.4), optimized for 425M rows

DROP TABLE IF EXISTS :results_schema.sepsis3_windows CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3_cohort CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3 CASCADE;

-- Performance settings for large table
SET work_mem = '8GB';
SET max_parallel_workers_per_gather = 4;
SET enable_nestloop = off;

-- 1) Build infection windows (Sepsis-3: baseline -24h, window -48h to +24h)
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
ANALYZE :results_schema.sepsis3_windows;

-- 2) Score SOFA and join in ONE pass (no correlated subqueries)
CREATE UNLOGGED TABLE :results_schema.sepsis3_enhanced AS
WITH sofa_scored AS (
  SELECT
    sh.person_id,
    sh.hr,
    -- respiratory
    CASE WHEN sh.pf_ratio IS NULL THEN 0
         WHEN sh.pf_ratio >= 400 THEN 0
         WHEN sh.pf_ratio >= 300 THEN 1
         WHEN sh.pf_ratio >= 200 THEN 2
         WHEN sh.pf_ratio >= 100 THEN 3
         ELSE 4 END
    +
    -- coagulation
    CASE WHEN sh.platelets IS NULL THEN 0
         WHEN sh.platelets > 150 THEN 0
         WHEN sh.platelets > 100 THEN 1
         WHEN sh.platelets > 50 THEN 2
         WHEN sh.platelets > 20 THEN 3
         ELSE 4 END
    +
    -- liver - MGH bilirubin in umol/L
    CASE WHEN sh.bilirubin IS NULL THEN 0
         WHEN sh.bilirubin/17.1 < 1.2 THEN 0
         WHEN sh.bilirubin/17.1 <= 1.9 THEN 1
         WHEN sh.bilirubin/17.1 <= 5.9 THEN 2
         WHEN sh.bilirubin/17.1 <= 11.9 THEN 3
         ELSE 4 END
    +
    -- cardiovascular - MAP only
    CASE WHEN sh.map IS NULL THEN 0
         WHEN sh.map >= 70 THEN 0
         ELSE 1 END
    +
    -- CNS
    CASE WHEN sh.gcs_total IS NULL THEN 0
         WHEN sh.gcs_total >= 15 THEN 0
         WHEN sh.gcs_total >= 13 THEN 1
         WHEN sh.gcs_total >= 10 THEN 2
         WHEN sh.gcs_total >= 6 THEN 3
         ELSE 4 END
    +
    -- renal - MGH creatinine in umol/L
    CASE WHEN sh.rrt_active THEN 4
         WHEN sh.urine_24h_ml IS NOT NULL AND sh.urine_24h_ml < 200 THEN 4
         WHEN sh.urine_24h_ml IS NOT NULL AND sh.urine_24h_ml < 500 THEN 3
         WHEN sh.creatinine IS NULL THEN 0
         WHEN sh.creatinine/88.4 < 1.2 THEN 0
         WHEN sh.creatinine/88.4 <= 1.9 THEN 1
         WHEN sh.creatinine/88.4 <= 3.4 THEN 2
         WHEN sh.creatinine/88.4 <= 4.9 THEN 3
         ELSE 4 END AS sofa_total
  FROM :results_schema.sofa_hourly sh
  WHERE EXISTS (  -- Only scan SOFA for patients with infections
    SELECT 1 FROM :results_schema.sepsis3_windows w 
    WHERE w.person_id = sh.person_id
  )
),
joined AS (
  SELECT
    w.person_id,
    w.infection_onset,
    w.baseline_start,
    w.window_start,
    w.window_end,
    w.antibiotic_time,
    w.culture_time,
    s.hr,
    s.sofa_total
  FROM :results_schema.sepsis3_windows w
  JOIN sofa_scored s
    ON s.person_id = w.person_id
   AND s.hr BETWEEN w.window_start AND w.window_end
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
FROM joined
GROUP BY person_id, infection_onset, baseline_start, window_end, antibiotic_time, culture_time;

ALTER TABLE :results_schema.sepsis3_enhanced SET LOGGED;
CREATE INDEX idx_sepsis3_enhanced_pid_onset 
  ON :results_schema.sepsis3_enhanced (person_id, infection_onset);
ANALYZE :results_schema.sepsis3_enhanced;

-- 3) Sepsis-3 cohort = delta >= 2
CREATE TABLE :results_schema.sepsis3_cohort AS
SELECT * FROM :results_schema.sepsis3_enhanced WHERE sofa_delta >= 2;

CREATE INDEX idx_sepsis3_cohort_pid_onset 
  ON :results_schema.sepsis3_cohort (person_id, infection_onset);

-- 4) Final table for compatibility
CREATE TABLE :results_schema.sepsis3 AS
SELECT * FROM :results_schema.sepsis3_cohort;

ANALYZE :results_schema.sepsis3_cohort;
ANALYZE :results_schema.sepsis3;

-- validation
SELECT 'sepsis3_windows' AS tbl, COUNT(*) AS n FROM :results_schema.sepsis3_windows
UNION ALL
SELECT 'sepsis3_enhanced', COUNT(*) FROM :results_schema.sepsis3_enhanced
UNION ALL
SELECT 'sepsis3_cohort (delta>=2)', COUNT(*) FROM :results_schema.sepsis3_cohort;
