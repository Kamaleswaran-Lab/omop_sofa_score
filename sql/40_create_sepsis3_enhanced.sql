-- 40_create_sepsis3_enhanced_FIXED.sql
-- Works with sofa_hourly that has total_sofa (not sofa_total)
-- Implements 24h pre-onset minimum baseline

DROP TABLE IF EXISTS results_site_a.sepsis3_enhanced CASCADE;

CREATE TABLE results_site_a.sepsis3_enhanced AS
WITH onset AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        infection_onset,
        infection_type
    FROM results_site_a.infection_onset_enhanced
),
sofa_window AS (
    SELECT 
        o.person_id,
        o.visit_occurrence_id,
        o.infection_onset,
        o.infection_type,
        s.charttime,
        s.total_sofa AS sofa_total,  -- <-- use your existing column
        EXTRACT(EPOCH FROM (s.charttime - o.infection_onset))/3600.0 AS hours_from_onset
    FROM onset o
    JOIN results_site_a.sofa_hourly s
      ON s.person_id = o.person_id
     AND s.charttime BETWEEN o.infection_onset - INTERVAL '48 hours'
                         AND o.infection_onset + INTERVAL '72 hours'
),
baseline_calc AS (
    SELECT
        person_id,
        visit_occurrence_id,
        infection_onset,
        infection_type,
        -- best baseline: minimum SOFA in 24h before onset
        MIN(sofa_total) FILTER (WHERE hours_from_onset BETWEEN -24 AND -1) AS baseline_24h_min,
        -- fallback: any SOFA in 24-48h before
        MAX(sofa_total) FILTER (WHERE hours_from_onset BETWEEN -48 AND -24) AS baseline_48h_any,
        -- peak in 72h after onset
        MAX(sofa_total) FILTER (WHERE hours_from_onset BETWEEN 0 AND 72) AS peak_72h
    FROM sofa_window
    GROUP BY person_id, visit_occurrence_id, infection_onset, infection_type
)
SELECT
    person_id,
    visit_occurrence_id,
    infection_onset,
    infection_type,
    COALESCE(baseline_24h_min, baseline_48h_any, 0) AS baseline_sofa,
    (baseline_24h_min IS NULL AND baseline_48h_any IS NULL) AS baseline_imputed,
    peak_72h AS peak_sofa,
    peak_72h - COALESCE(baseline_24h_min, baseline_48h_any, 0) AS delta_sofa,
    (peak_72h - COALESCE(baseline_24h_min, baseline_48h_any, 0)) >= 2 AS meets_sepsis3
FROM baseline_calc
WHERE peak_72h IS NOT NULL;

CREATE INDEX idx_sepsis3_enhanced_person ON results_site_a.sepsis3_enhanced(person_id, infection_onset);
CREATE INDEX idx_sepsis3_enhanced_visit ON results_site_a.sepsis3_enhanced(visit_occurrence_id);
