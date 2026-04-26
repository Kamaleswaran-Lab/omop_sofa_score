-- RUN_ALL_master.sql
-- MGH Sepsis Pipeline - Full Rebuild
-- Run from psql: \i RUN_ALL_master.sql

\echo '=== 0. Schemas ==='
\ir 00_create_schemas.sql

\echo '=== 1. Core views ==='
\ir 10_view_labs_core.sql
\ir 11_view_vitals_core.sql
\ir 14_view_neuro.sql
\ir 15_view_urine_24h.sql

\echo '=== 2. Respiratory ==='
\ir 20_view_pao2_fio2_pairs.sql

\echo '=== 3. Microbiology ==='
\ir 22_view_cultures.sql

\echo '=== 4. SOFA components ==='
\ir 30_view_sofa_daily.sql

\echo '=== 5. ASE cohort ==='
\ir 40_build_ase_cohort.sql

\echo '=== 6. Sepsis-3 cohort ==='
\ir 41_build_sepsis3_cohort.sql

\echo '=== 7. Comparison table ==='
\ir 42_build_cohort_comparison.sql

\echo '=== 8. Indexes and analyze ==='
CREATE INDEX IF NOT EXISTS idx_ase_person ON results_site_a.cdc_ase_cohort_final(person_id);
CREATE INDEX IF NOT EXISTS idx_ase_onset ON results_site_a.cdc_ase_cohort_final(infection_onset);
CREATE INDEX IF NOT EXISTS idx_sepsis_person ON results_site_a.sepsis_cohort_comparison(person_id);
CREATE INDEX IF NOT EXISTS idx_sepsis_onset ON results_site_a.sepsis_cohort_comparison(sepsis3_onset);

ANALYZE results_site_a.cdc_ase_cohort_final;
ANALYZE results_site_a.sepsis_cohort_comparison;
ANALYZE results_site_a.view_pao2_fio2_pairs;

\echo '=== DONE ==='
SELECT 'ASE' as cohort, COUNT(*) FROM results_site_a.cdc_ase_cohort_final
UNION ALL
SELECT 'Sepsis-3', COUNT(*) FROM results_site_a.sepsis_cohort_comparison WHERE sepsis3_onset IS NOT NULL;
