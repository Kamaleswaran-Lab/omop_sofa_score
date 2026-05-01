-- 41_create_sepsis3_collapsed_48h.sql
-- Collapse Sepsis-3 events within 48 hours into single episodes

DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced_collapsed CASCADE;

CREATE TABLE :results_schema.sepsis3_enhanced_collapsed AS
WITH ordered AS (
  SELECT *,
    LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) AS prev_onset
  -- FIX 2: Query the pre-filtered cohort table, not the massive enhanced table
  FROM :results_schema.sepsis3_cohort 
),
grouped AS (
  SELECT *,
    SUM(CASE 
          WHEN prev_onset IS NULL OR infection_onset > prev_onset + INTERVAL '48 hours' 
          THEN 1 ELSE 0 
        END) OVER (PARTITION BY person_id ORDER BY infection_onset) AS episode_grp
  FROM ordered
)
SELECT 
  person_id,
  MIN(infection_onset) AS infection_onset,
  MIN(baseline_start) AS baseline_start,
  MAX(window_end) AS window_end,
  MIN(antibiotic_time) AS antibiotic_time,
  MIN(culture_time) AS culture_time,
  MIN(baseline_sofa) AS baseline_sofa,
  MAX(max_sofa) AS max_sofa,
  -- FIX 1: Recalculate the true delta for the new collapsed timeframe
  (MAX(max_sofa) - MIN(baseline_sofa)) AS sofa_delta 
FROM grouped
GROUP BY person_id, episode_grp;

CREATE INDEX idx_sepsis3_collapsed_pid ON :results_schema.sepsis3_enhanced_collapsed (person_id);
ANALYZE :results_schema.sepsis3_enhanced_collapsed;
