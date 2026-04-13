-- Sepsis-3 cases with pre-infection baseline
DROP TABLE IF EXISTS results_site_a.sepsis3_cases CASCADE;

CREATE TABLE results_site_a.sepsis3_cases AS
WITH baseline AS (
    SELECT 
        i.person_id,
        i.infection_onset,
        (
            SELECT MAX(s.total_sofa)
            FROM results_site_a.sofa_hourly s
            WHERE s.person_id = i.person_id
            AND s.charttime BETWEEN i.infection_onset - INTERVAL '72 hours' 
                AND i.infection_onset - INTERVAL '1 hour'
        ) AS baseline_sofa
    FROM results_site_a.vw_infection_onset i
),
window_max AS (
    SELECT 
        i.person_id,
        i.infection_onset,
        (
            SELECT MAX(s.total_sofa)
            FROM results_site_a.sofa_hourly s
            WHERE s.person_id = i.person_id
            AND s.charttime BETWEEN i.infection_onset - INTERVAL '48 hours'
                AND i.infection_onset + INTERVAL '24 hours'
        ) AS peak_sofa
    FROM results_site_a.vw_infection_onset i
)
SELECT 
    b.person_id,
    b.infection_onset,
    COALESCE(b.baseline_sofa, 0) AS baseline_sofa,
    w.peak_sofa,
    w.peak_sofa - COALESCE(b.baseline_sofa, 0) AS delta_sofa,
    b.infection_onset AS sepsis_onset,
    'pre_infection_72h' AS baseline_method
FROM baseline b
JOIN window_max w USING (person_id, infection_onset)
WHERE w.peak_sofa - COALESCE(b.baseline_sofa, 0) >= 2;

CREATE INDEX idx_sepsis3_person ON results_site_a.sepsis3_cases(person_id);