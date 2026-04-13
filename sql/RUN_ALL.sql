-- MASTER SCRIPT - Run all SQL files in order
-- Site A SOFA/Sepsis-3 Implementation

\i 00_create_schemas.sql
\i 01_create_assumptions_table.sql
\i 02_create_indexes.sql
\i 10_view_labs_core.sql
\i 11_view_vitals_core.sql
\i 12_view_vasopressors_nee.sql
\i 13_view_ventilation.sql
\i 14_view_neuro.sql
\i 15_view_urine_24h.sql
\i 16_view_rrt.sql
\i 20_view_pao2_fio2_pairs.sql
\i 21_view_antibiotics.sql
\i 22_view_cultures.sql
\i 23_view_infection_onset.sql
\i 30_view_sofa_components.sql
\i 31_create_sofa_hourly.sql
\i 40_create_sepsis3.sql

-- Verify
SELECT 'Labs' as view, COUNT(*) FROM results_site_a.vw_labs_core
UNION ALL
SELECT 'Vitals', COUNT(*) FROM results_site_a.vw_vitals_core
UNION ALL
SELECT 'SOFA hourly', COUNT(*) FROM results_site_a.sofa_hourly
UNION ALL
SELECT 'Sepsis-3', COUNT(*) FROM results_site_a.sepsis3_cases;
