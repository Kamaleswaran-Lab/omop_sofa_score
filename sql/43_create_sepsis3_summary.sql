-- Summary view - corrected columns
DROP VIEW IF EXISTS :results_schema.sepsis3_summary CASCADE;
CREATE VIEW :results_schema.sepsis3_summary AS
WITH icu_den AS (
    SELECT COUNT(DISTINCT vd.person_id) AS icu_patients
    FROM :cdm_schema.visit_detail vd
    JOIN :results_schema.assumptions a ON a.domain='icu' AND a.concept_id = vd.visit_detail_concept_id
),
strict AS (
    SELECT COUNT(DISTINCT person_id) AS patients, COUNT(*) AS episodes FROM :results_schema.sepsis3_cases
),
enhanced AS (
    SELECT COUNT(DISTINCT person_id) AS patients, COUNT(*) AS episodes FROM :results_schema.sepsis3_enhanced_collapsed
),
outcomes AS (
    SELECT AVG(max_delta_sofa) AS mean_delta, SUM(death_30d::int) AS deaths, SUM(hospice_30d::int) AS hospice, SUM(composite_30d::int) AS composite, COUNT(*) AS n
    FROM :results_schema.sepsis3_outcomes_30d
)
SELECT (SELECT icu_patients FROM icu_den) AS icu_denominator,
       (SELECT patients FROM strict) AS strict_patients,
       (SELECT patients FROM enhanced) AS enhanced_patients,
       ROUND(100.0 * (SELECT patients FROM enhanced) / NULLIF((SELECT icu_patients FROM icu_den),0),1) AS prevalence_pct,
       ROUND((SELECT mean_delta FROM outcomes),1) AS mean_delta_sofa,
       (SELECT deaths FROM outcomes) AS deaths_30d,
       (SELECT hospice FROM outcomes) AS hospice_30d,
       (SELECT composite FROM outcomes) AS composite_30d,
       ROUND(100.0 * (SELECT composite FROM outcomes) / NULLIF((SELECT n FROM outcomes),0),1) AS composite_pct;
