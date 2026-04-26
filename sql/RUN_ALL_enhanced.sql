-- RUN_ALL_enhanced_FIXED.sql
\echo '=== 0. Schemas ==='
\ir 00_create_schemas.sql

\echo '=== 1. Core views ==='
\ir 10_view_labs_core.sql
\ir 11_view_vitals_core.sql
\ir 14_view_neuro.sql
\ir 15_view_urine_24h.sql
\ir 16_view_rrt.sql

\echo '=== 2. Respiratory & support ==='
\ir 20_view_pao2_fio2_pairs.sql
\ir 12_view_vasopressors_nee.sql
\ir 13_view_ventilation.sql

\echo '=== 3. Microbiology ==='
\ir 22_view_cultures.sql
\ir 21_view_antibiotics.sql
\ir 23_view_infection_onset_enhanced.sql

\echo '=== 4. SOFA components ==='
\ir 30_view_sofa_components.sql
\ir 31_create_sofa_hourly.sql

\echo '=== 5. Sepsis-3 ==='
\ir 40_create_sepsis3_enhanced.sql
\ir 41_create_sepsis3_collapsed_48h.sql

\echo '=== 6. CDC ASE ==='
\ir 50_cdc_ase_parameters.sql
\ir 51_cdc_ase_blood_cultures.sql
\ir 52_cdc_ase_qad.sql
\ir 53_cdc_ase_organ_dysfunction.sql
\ir 54_cdc_ase_cases.sql
\ir 55_cdc_ase_with_sofa.sql
\ir 56_cdc_ase_cohort_final.sql

\echo '=== 7. Comparison ==='
\ir 61_create_sepsis_cohort_comparison.sql
\ir 60_sepsis_combined_sep3_ASE_characteristics.sql

\echo '=== 8. Analyze ==='
ANALYZE :results_schema.cdc_ase_cohort_final;
ANALYZE :results_schema.sepsis_cohort_comparison;
