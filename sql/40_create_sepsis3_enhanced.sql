-- ============================================================================
-- 40_create_sepsis3_enhanced.sql
-- Sepsis-3 Enhanced Cohort with Proper 24h Baseline
-- 
-- Compatible with sofa_hourly schema:
--   total_sofa, resp_sofa, cardio_sofa, neuro_sofa, 
--   renal_sofa, hepatic_sofa, coag_sofa
-- ============================================================================

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
        s.total_sofa AS sofa_total,
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
        -- Primary baseline: minimum SOFA in 24h BEFORE onset (Sepsis-3 standard)
        MIN(sofa_total) FILTER (WHERE hours_from_onset BETWEEN -24 AND -1) AS baseline_24h_min,
        -- Fallback 1: any SOFA in 24-48h before (if no data in last 24h)
        MAX(sofa_total) FILTER (WHERE hours_from_onset BETWEEN -48 AND -24) AS baseline_48h_any,
        -- Peak SOFA in 72h AFTER onset
        MAX(sofa_total) FILTER (WHERE hours_from_onset BETWEEN 0 AND 72) AS peak_72h,
        -- Count of pre-onset measurements for quality tracking
        COUNT(*) FILTER (WHERE hours_from_onset BETWEEN -24 AND -1) AS n_baseline_24h,
        COUNT(*) FILTER (WHERE hours_from_onset BETWEEN -48 AND 0) AS n_baseline_48h
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
    n_baseline_24h,
    n_baseline_48h,
    peak_72h AS peak_sofa,
    peak_72h - COALESCE(baseline_24h_min, baseline_48h_any, 0) AS delta_sofa,
    (peak_72h - COALESCE(baseline_24h_min, baseline_48h_any, 0)) >= 2 AS meets_sepsis3
FROM baseline_calc
WHERE peak_72h IS NOT NULL;

-- Indexes for performance
CREATE INDEX idx_sepsis3_enhanced_person ON results_site_a.sepsis3_enhanced(person_id, infection_onset);
CREATE INDEX idx_sepsis3_enhanced_visit ON results_site_a.sepsis3_enhanced(visit_occurrence_id);
CREATE INDEX idx_sepsis3_enhanced_meets ON results_site_a.sepsis3_enhanced(meets_sepsis3) WHERE meets_sepsis3 = true;

-- Validation view
COMMENT ON TABLE results_site_a.sepsis3_enhanced IS 'Sepsis-3 cohort with 24h pre-onset baseline. baseline_imputed=true means no pre-onset SOFA data, baseline assumed 0.';
