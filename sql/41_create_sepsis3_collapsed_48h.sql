-- v4.5 Collapse episodes <48h apart
DROP TABLE IF EXISTS {{results_schema}}.sepsis3_enhanced_collapsed CASCADE;

CREATE TABLE {{results_schema}}.sepsis3_enhanced_collapsed AS
WITH ordered AS (
    SELECT
        *,
        LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) AS prev_onset
    FROM {{results_schema}}.sepsis3_enhanced
)
SELECT
    person_id,
    infection_onset,
    infection_type,
    icu_onset,
    distinct_abx_count,
    total_abx_days,
    has_culture,
    baseline_sofa,
    peak_sofa,
    delta_sofa,
    prev_onset,
    CASE WHEN prev_onset IS NULL THEN 1 ELSE 0 END AS is_first_episode
FROM ordered
WHERE prev_onset IS NULL
   OR infection_onset - prev_onset > INTERVAL '48 hours';

CREATE INDEX idx_collapsed_person ON {{results_schema}}.sepsis3_enhanced_collapsed(person_id);
