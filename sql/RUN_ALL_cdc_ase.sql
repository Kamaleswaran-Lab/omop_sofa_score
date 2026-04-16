-- RUN_ALL_cdc_ase.sql
-- CDC Adult Sepsis Event implementation for OMOP CDM
-- FIXED VERSION: Includes ICU patients (removed restrictive visit filter)
-- Integrates with Kamaleswaran-Lab omop_sofa_score repo
-- Updated: 2026-04-15

\set cdm_schema omopcdm
\set vocab_schema vocabulary
\set results_schema results_site_a

-- Step 1: Parameters and concept sets
\i sql/50_cdc_ase_parameters.sql

-- Step 2: Blood cultures (presumed infection start)
\i sql/51_cdc_ase_blood_cultures.sql

-- Step 3: Qualifying antimicrobial days (QAD)
\i sql/52_cdc_ase_qad.sql

-- Step 4: Organ dysfunction
\i sql/53_cdc_ase_organ_dysfunction.sql

-- Step 5: Final ASE cases (FIXED: now includes ICU)
\i sql/54_cdc_ase_cases.sql

-- Step 6: Join with SOFA scores
\i sql/55_cdc_ase_with_sofa.sql

-- Step 7: Add outcomes and organ support (FINAL COHORT)
\i sql/56_cdc_ase_cohort_final.sql

-- ============================================================================
-- SUMMARY REPORTS
-- ============================================================================

\echo ''
\echo '========================================'
\echo 'CDC ASE COHORT SUMMARY (ICU-INCLUSIVE)'
\echo '========================================'
\echo ''

-- Basic counts
SELECT 
    'Total Episodes' AS metric, 
    COUNT(*)::text AS value
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT 
    'Unique Patients', 
    COUNT(DISTINCT person_id)::text
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT 
    'Study Period', 
    MIN(onset_date)::text || ' to ' || MAX(onset_date)::text
FROM :results_schema.cdc_ase_cohort_final;

\echo ''
\echo '--- Onset Type ---'
SELECT 
    onset_type, 
    COUNT(*) AS cases, 
    COUNT(DISTINCT person_id) AS patients,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM :results_schema.cdc_ase_cohort_final
GROUP BY onset_type
ORDER BY cases DESC;

\echo ''
\echo '--- Location Distribution ---'
SELECT 
    COALESCE(visit_type, 'Unknown') AS location,
    COUNT(*) AS n,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM :results_schema.cdc_ase_cohort_final
GROUP BY visit_type
ORDER BY n DESC
LIMIT 15;

\echo ''
\echo '--- Severity (SOFA) ---'
SELECT
    sofa_severity,
    COUNT(*) AS n,
    ROUND(AVG(max_sofa_72h),1) AS mean_sofa,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM :results_schema.cdc_ase_cohort_final
GROUP BY sofa_severity
ORDER BY 
    CASE sofa_severity 
        WHEN 'minimal' THEN 1
        WHEN 'mild' THEN 2
        WHEN 'moderate' THEN 3
        WHEN 'severe' THEN 4
    END;

\echo ''
\echo '--- Organ Support ---'
SELECT
    'ICU Admission' AS support,
    SUM(icu_admission) AS n,
    ROUND(100.0 * SUM(icu_admission) / COUNT(*), 1) AS pct
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT
    'Vasopressors (72h)',
    SUM(vasopressor_72h),
    ROUND(100.0 * SUM(vasopressor_72h) / COUNT(*), 1)
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT
    'Mechanical Ventilation (72h)',
    SUM(ventilation_72h),
    ROUND(100.0 * SUM(ventilation_72h) / COUNT(*), 1)
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT
    'Any Organ Support',
    SUM(organ_support),
    ROUND(100.0 * SUM(organ_support) / COUNT(*), 1)
FROM :results_schema.cdc_ase_cohort_final;

\echo ''
\echo '--- Outcomes ---'
SELECT
    'In-Hospital Mortality' AS outcome,
    SUM(died_in_hospital) AS n,
    ROUND(100.0 * SUM(died_in_hospital) / COUNT(*), 1) AS pct
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT
    '30-Day Mortality',
    SUM(died_30d),
    ROUND(100.0 * SUM(died_30d) / COUNT(*), 1)
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT
    'Mean Hospital LOS (days)',
    NULL,
    ROUND(AVG(hospital_los_days),1)
FROM :results_schema.cdc_ase_cohort_final;

\echo ''
\echo '--- Comparison to Other Definitions ---'
SELECT 'CDC_ASE' AS definition, COUNT(*) AS n 
FROM :results_schema.cdc_ase_cohort_final
UNION ALL
SELECT 'CDC_ASE_Community', COUNT(*) 
FROM :results_schema.cdc_ase_cohort_final 
WHERE onset_type = 'community-onset'
UNION ALL
SELECT 'CDC_ASE_Hospital', COUNT(*) 
FROM :results_schema.cdc_ase_cohort_final 
WHERE onset_type = 'hospital-onset'
UNION ALL
SELECT 'Sepsis3_enhanced', COUNT(*) 
FROM :results_schema.sepsis3_enhanced
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'sepsis3_enhanced');

\echo ''
\echo '========================================'
\echo 'Cohort ready: :results_schema.cdc_ase_cohort_final'
\echo '========================================'
\echo ''
