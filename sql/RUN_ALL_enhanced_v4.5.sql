-- ============================================================================
-- OMOP SOFA v4.5 – RUN_ALL_enhanced.sql
-- Enhanced Sepsis-3: 96h culture, 48h collapse, ICU-onset, 30d death/hospice
-- ============================================================================
\set ON_ERROR_STOP on
\echo '=== v4.5 Enhanced Sepsis-3 Pipeline ==='

-- Set schemas (override with -v on command line)
\if :{?cdm_schema} \else \set cdm_schema omopcdm \endif
\if :{?vocab_schema} \else \set vocab_schema vocabulary \endif
\if :{?results_schema} \else \set results_schema results_site_a \endif

\echo 'Using schemas:'
\echo '  CDM: :'cdm_schema
\echo '  Vocab: :'vocab_schema
\echo '  Results: :'results_schema

-- ----------------------------------------------------------------------------
-- 1) Enhanced infection onset view
-- ----------------------------------------------------------------------------
\echo '[1/5] Creating view_infection_onset_enhanced...'
DROP VIEW IF EXISTS :"results_schema".view_infection_onset_enhanced CASCADE;

CREATE VIEW :"results_schema".view_infection_onset_enhanced AS
WITH abx AS (
    SELECT person_id, drug_exposure_start_datetime AS abx_time, drug_concept_id
    FROM :"cdm_schema".drug_exposure de
    JOIN :"vocab_schema".concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
    WHERE ca.ancestor_concept_id IN (21602796) -- antibacterials
      AND de.drug_exposure_start_datetime IS NOT NULL
),
abx_courses AS (
    SELECT person_id, abx_time, drug_concept_id,
           SUM(CASE WHEN LAG(abx_time) OVER (PARTITION BY person_id ORDER BY abx_time) IS NULL
                     OR abx_time - LAG(abx_time) OVER (PARTITION BY person_id ORDER BY abx_time) > INTERVAL '24 hours'
                THEN 1 ELSE 0 END)
           OVER (PARTITION BY person_id ORDER BY abx_time) AS course_id
    FROM abx
),
courses AS (
    SELECT person_id, MIN(abx_time) AS infection_onset,
           COUNT(DISTINCT drug_concept_id) AS distinct_abx_count,
           DATE_PART('day', MAX(abx_time) - MIN(abx_time)) + 1 AS total_abx_days
    FROM abx_courses GROUP BY person_id, course_id
),
cultures AS (
    SELECT person_id, COALESCE(measurement_datetime, specimen_datetime) AS culture_time
    FROM :"cdm_schema".measurement m
    JOIN :"vocab_schema".concept_ancestor ca ON ca.descendant_concept_id = m.measurement_concept_id
    WHERE ca.ancestor_concept_id = 40484543
    UNION
    SELECT person_id, specimen_datetime
    FROM :"cdm_schema".specimen s
    JOIN :"vocab_schema".concept_ancestor ca ON ca.descendant_concept_id = s.specimen_concept_id
    WHERE ca.ancestor_concept_id = 40484543
),
icu_stays AS (
    SELECT person_id, visit_detail_start_datetime, visit_detail_end_datetime
    FROM :"cdm_schema".visit_detail
    WHERE visit_detail_concept_id IN (2072499989,581383,2072500011,2072500012,2072500018,2072500007,2072500031,2072500010,2072500004)
)
SELECT c.person_id, c.infection_onset,
       CASE WHEN EXISTS (SELECT 1 FROM cultures cu WHERE cu.person_id=c.person_id
              AND cu.culture_time BETWEEN c.infection_onset - INTERVAL '24 hours' AND c.infection_onset + INTERVAL '96 hours')
            THEN 'culture_positive'
            WHEN c.distinct_abx_count >= 2 THEN 'multi_abx'
            ELSE 'single_abx_icu' END AS infection_type,
       c.distinct_abx_count, c.total_abx_days,
       EXISTS (SELECT 1 FROM cultures cu WHERE cu.person_id=c.person_id
              AND cu.culture_time BETWEEN c.infection_onset - INTERVAL '24 hours' AND c.infection_onset + INTERVAL '96 hours') AS has_culture,
       c.infection_onset - INTERVAL '72 hours' AS baseline_start,
       c.infection_onset + INTERVAL '48 hours' AS organ_dysfunction_end,
       CASE WHEN EXISTS (SELECT 1 FROM icu_stays i WHERE i.person_id=c.person_id
              AND c.infection_onset BETWEEN i.visit_detail_start_datetime AND i.visit_detail_end_datetime)
            THEN 1 ELSE 0 END AS icu_onset
FROM courses c
WHERE c.infection_onset < CURRENT_DATE
  AND (c.distinct_abx_count >= 2 OR EXISTS (SELECT 1 FROM cultures cu WHERE cu.person_id=c.person_id
              AND cu.culture_time BETWEEN c.infection_onset - INTERVAL '24 hours' AND c.infection_onset + INTERVAL '96 hours')
       OR 1=1); -- keep single_abx for ICU filter later

-- ----------------------------------------------------------------------------
-- 2) Sepsis-3 enhanced table (ΔSOFA ≥2)
-- ----------------------------------------------------------------------------
\echo '[2/5] Creating sepsis3_enhanced...'
DROP TABLE IF EXISTS :"results_schema".sepsis3_enhanced CASCADE;
CREATE TABLE :"results_schema".sepsis3_enhanced AS
SELECT i.person_id, i.infection_onset, i.infection_type, i.icu_onset,
       i.distinct_abx_count, i.total_abx_days, i.has_culture,
       MIN(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.baseline_start AND i.infection_onset) AS baseline_sofa,
       MAX(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.infection_onset AND i.organ_dysfunction_end) AS peak_sofa,
       MAX(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.infection_onset AND i.organ_dysfunction_end) -
       MIN(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.baseline_start AND i.infection_onset) AS delta_sofa
FROM :"results_schema".view_infection_onset_enhanced i
LEFT JOIN :"results_schema".sofa_hourly s ON s.person_id = i.person_id
GROUP BY 1,2,3,4,5,6,7
HAVING MAX(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.infection_onset AND i.organ_dysfunction_end) -
       MIN(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.baseline_start AND i.infection_onset) >= 2;

CREATE INDEX ON :"results_schema".sepsis3_enhanced(person_id);
CREATE INDEX ON :"results_schema".sepsis3_enhanced(infection_onset);
CREATE INDEX ON :"results_schema".sepsis3_enhanced(icu_onset);

-- ----------------------------------------------------------------------------
-- 3) 48-hour collapse
-- ----------------------------------------------------------------------------
\echo '[3/5] Creating sepsis3_enhanced_collapsed (48h)...'
DROP TABLE IF EXISTS :"results_schema".sepsis3_enhanced_collapsed CASCADE;
CREATE TABLE :"results_schema".sepsis3_enhanced_collapsed AS
WITH ordered AS (
    SELECT *, LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) AS prev_onset
    FROM :"results_schema".sepsis3_enhanced
)
SELECT * FROM ordered
WHERE prev_onset IS NULL OR infection_onset - prev_onset > INTERVAL '48 hours';

CREATE INDEX ON :"results_schema".sepsis3_enhanced_collapsed(person_id);

-- ----------------------------------------------------------------------------
-- 4) 30-day outcomes (death OR hospice)
-- ----------------------------------------------------------------------------
\echo '[4/5] Creating sepsis3_outcomes_30d...'
DROP TABLE IF EXISTS :"results_schema".sepsis3_outcomes_30d CASCADE;
CREATE TABLE :"results_schema".sepsis3_outcomes_30d AS
WITH first_episode AS (
    SELECT person_id, MIN(infection_onset) AS first_onset,
           MIN(baseline_sofa) AS baseline_sofa, MAX(peak_sofa) AS peak_sofa,
           MAX(delta_sofa) AS max_delta_sofa, COUNT(*) AS total_episodes
    FROM :"results_schema".sepsis3_enhanced_collapsed WHERE icu_onset=1 GROUP BY person_id
),
index_adm AS (
    SELECT DISTINCT ON (f.person_id) f.person_id, vo.visit_end_date, vo.discharged_to_concept_id
    FROM first_episode f
    JOIN :"cdm_schema".visit_occurrence vo ON vo.person_id=f.person_id
      AND f.first_onset BETWEEN vo.visit_start_datetime AND vo.visit_end_datetime
    ORDER BY f.person_id, vo.visit_start_datetime
)
SELECT f.person_id, f.first_onset, f.baseline_sofa, f.peak_sofa, f.max_delta_sofa, f.total_episodes,
       d.death_date,
       CASE WHEN d.death_date BETWEEN f.first_onset::date AND f.first_onset::date + 30 THEN 1 ELSE 0 END AS death_30d,
       CASE WHEN ia.discharged_to_concept_id = 8546 AND ia.visit_end_date BETWEEN f.first_onset::date AND f.first_onset::date + 30 THEN 1 ELSE 0 END AS hospice_30d,
       CASE WHEN (d.death_date BETWEEN f.first_onset::date AND f.first_onset::date + 30) OR
                 (ia.discharged_to_concept_id = 8546 AND ia.visit_end_date BETWEEN f.first_onset::date AND f.first_onset::date + 30)
            THEN 1 ELSE 0 END AS death_or_hospice_30d
FROM first_episode f
LEFT JOIN :"cdm_schema".death d ON d.person_id=f.person_id
LEFT JOIN index_adm ia ON ia.person_id=f.person_id;

-- ----------------------------------------------------------------------------
-- 5) Summary view
-- ----------------------------------------------------------------------------
\echo '[5/5] Creating sepsis3_summary...'
DROP VIEW IF EXISTS :"results_schema".sepsis3_summary CASCADE;
CREATE VIEW :"results_schema".sepsis3_summary AS
WITH icu AS (SELECT COUNT(DISTINCT person_id) AS n FROM :"cdm_schema".visit_detail
             WHERE visit_detail_concept_id IN (2072499989,581383,2072500011,2072500012,2072500018,2072500007,2072500031,2072500010,2072500004))
SELECT (SELECT n FROM icu) AS icu_denominator,
       (SELECT COUNT(DISTINCT person_id) FROM :"results_schema".sepsis3_cases) AS strict_patients,
       (SELECT COUNT(DISTINCT person_id) FROM :"results_schema".sepsis3_enhanced_collapsed WHERE icu_onset=1) AS enhanced_patients,
       ROUND(100.0*(SELECT COUNT(DISTINCT person_id) FROM :"results_schema".sepsis3_enhanced_collapsed WHERE icu_onset=1)/(SELECT n FROM icu),1) AS prevalence_pct,
       (SELECT ROUND(AVG(max_delta_sofa),1) FROM :"results_schema".sepsis3_outcomes_30d) AS mean_delta_sofa,
       (SELECT SUM(death_30d) FROM :"results_schema".sepsis3_outcomes_30d) AS deaths_30d,
       (SELECT SUM(hospice_30d) FROM :"results_schema".sepsis3_outcomes_30d) AS hospice_30d,
       (SELECT SUM(death_or_hospice_30d) FROM :"results_schema".sepsis3_outcomes_30d) AS composite_30d,
       (SELECT ROUND(100.0*SUM(death_or_hospice_30d)/COUNT(*),1) FROM :"results_schema".sepsis3_outcomes_30d) AS composite_pct;

\echo '=== Complete ==='
SELECT * FROM :"results_schema".sepsis3_summary;
