-- v4.5 Final summary view
DROP VIEW IF EXISTS {{results_schema}}.sepsis3_summary CASCADE;

CREATE VIEW {{results_schema}}.sepsis3_summary AS
WITH icu_den AS (
    SELECT COUNT(DISTINCT person_id) AS icu_patients
    FROM {{cdm_schema}}.visit_detail
    WHERE visit_detail_concept_id IN (
        2072499989,581383,2072500011,2072500012,
        2072500018,2072500007,2072500031,2072500010,2072500004
    )
),
strict AS (
    SELECT COUNT(DISTINCT person_id) AS patients, COUNT(*) AS episodes
    FROM {{results_schema}}.sepsis3_cases
),
enhanced AS (
    SELECT COUNT(DISTINCT person_id) AS patients, COUNT(*) AS episodes
    FROM {{results_schema}}.sepsis3_enhanced_collapsed
    WHERE icu_onset = 1
)
SELECT
    (SELECT icu_patients FROM icu_den) AS icu_denominator,
    (SELECT patients FROM strict) AS sepsis_strict_patients,
    (SELECT episodes FROM strict) AS sepsis_strict_episodes,
    (SELECT patients FROM enhanced) AS sepsis_enhanced_patients,
    (SELECT episodes FROM enhanced) AS sepsis_enhanced_episodes,
    ROUND(100.0 * (SELECT patients FROM enhanced) / (SELECT icu_patients FROM icu_den), 1) AS prevalence_pct,
    (SELECT ROUND(AVG(max_delta_sofa),1) FROM {{results_schema}}.sepsis3_outcomes_30d) AS mean_delta_sofa,
    (SELECT SUM(death_30d) FROM {{results_schema}}.sepsis3_outcomes_30d) AS deaths_30d,
    (SELECT SUM(hospice_30d) FROM {{results_schema}}.sepsis3_outcomes_30d) AS hospice_30d,
    (SELECT SUM(death_or_hospice_30d) FROM {{results_schema}}.sepsis3_outcomes_30d) AS composite_30d,
    (SELECT ROUND(100.0 * SUM(death_or_hospice_30d) / COUNT(*),1)
     FROM {{results_schema}}.sepsis3_outcomes_30d) AS composite_mortality_pct;
