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
        s.sofa_total,
        EXTRACT(EPOCH FROM (s.charttime - o.infection_onset))/3600 AS hours_from_onset
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
        -- Best baseline: minimum SOFA in 24h before onset
        MIN(sofa_total) FILTER (WHERE hours_from_onset BETWEEN -24 AND -1) AS baseline_24h_min,
        -- Fallback: last SOFA in 24-48h before
        (SELECT sofa_total FROM sofa_window sw2 
         WHERE sw2.person_id = sw.person_id 
           AND sw2.visit_occurrence_id = sw.visit_occurrence_id
           AND sw2.hours_from_onset BETWEEN -48 AND -24
         ORDER BY sw2.charttime DESC LIMIT 1) AS baseline_48h_last,
        MAX(sofa_total) FILTER (WHERE hours_from_onset BETWEEN 0 AND 72) AS peak_72h,
        MIN(charttime) FILTER (WHERE hours_from_onset BETWEEN 0 AND 72) AS first_sofa_time
    FROM sofa_window sw
    GROUP BY person_id, visit_occurrence_id, infection_onset, infection_type
)
SELECT
    person_id,
    visit_occurrence_id,
    infection_onset,
    infection_type,
    COALESCE(baseline_24h_min, baseline_48h_last, 0) AS baseline_sofa,
    (baseline_24h_min IS NULL AND baseline_48h_last IS NULL) AS baseline_imputed,
    peak_72h AS peak_sofa,
    peak_72h - COALESCE(baseline_24h_min, baseline_48h_last, 0) AS delta_sofa,
    (peak_72h - COALESCE(baseline_24h_min, baseline_48h_last, 0)) >= 2 AS meets_sepsis3
FROM baseline_calc
WHERE peak_72h IS NOT NULL;

CREATE INDEX ON results_site_a.sepsis3_enhanced(person_id, infection_onset);
