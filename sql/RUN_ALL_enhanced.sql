-- RUN_ALL_MGH_TUNED.sql - Kamaleswaran-Lab repo + Azure performance fix
\set results_schema results_site_a
\set cdm_schema omopcdm
\set vocab_schema vocabulary

-- Global tuning for this session only
SET work_mem = '4GB';
SET maintenance_work_mem = '2GB';
SET max_parallel_workers_per_gather = 0;  -- prevents IPC MessageQueueSend
SET temp_buffers = '1GB';
SET synchronous_commit = off;
SET statement_timeout = 0;

\ir 00_create_schemas.sql
\ir 01_create_assumptions_table.sql
\ir 10_view_labs_core.sql
\ir 11_view_vitals_core.sql
\ir 12_view_vasopressors_nee.sql
\ir 13_view_ventilation.sql
\ir 14_view_neuro.sql
\ir 15_view_urine_24h.sql
\ir 16_view_rrt.sql

-- Fix PF view first
DROP VIEW IF EXISTS :results_schema.view_pao2_fio2_pairs CASCADE;
\ir 20_view_pao2_fio2_pairs.sql

-- Recreate with CASCADE to avoid "cannot drop columns"
DROP VIEW IF EXISTS :results_schema.view_antibiotics CASCADE;
\ir 21_view_antibiotics.sql
DROP VIEW IF EXISTS :results_schema.view_cultures CASCADE;
\ir 22_view_cultures.sql
DROP VIEW IF EXISTS :results_schema.view_infection_onset CASCADE;
\ir 23_view_infection_onset.sql

-- Patch SOFA components for pao2_datetime
DROP VIEW IF EXISTS :results_schema.vw_sofa_components CASCADE;
\ir 30_view_sofa_components.sql
-- If error about pao2_time, run this manual fix once:
-- \! sed -i 's/pao2_time/pao2_datetime/g' 30_view_sofa_components.sql

-- TUNED sofa_hourly build (replaces 31_create_sofa_hourly.sql)
DROP TABLE IF EXISTS :results_schema.sofa_hourly CASCADE;
CREATE UNLOGGED TABLE :results_schema.sofa_hourly AS
SELECT * FROM :results_schema.vw_sofa_components;
ALTER TABLE :results_schema.sofa_hourly SET LOGGED;

-- Sepsis-3
DROP TABLE IF EXISTS :results_schema.sepsis3 CASCADE;
\ir 40_create_sepsis3.sql
DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced CASCADE;
\ir 40_create_sepsis3_enhanced.sql
DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced_collapsed CASCADE;
\ir 41_create_sepsis3_collapsed_48h.sql

-- ASE - must replace Jinja first
\! sed -i 's/{{results_schema}}/:results_schema/g; s/{{cdm_schema}}/:cdm_schema/g; s/{{vocab_schema}}/:vocab_schema/g' 5*.sql
\ir 50_cdc_ase_parameters.sql
\ir 51_cdc_ase_blood_cultures.sql
\ir 52_cdc_ase_qad.sql
\ir 53_cdc_ase_organ_dysfunction.sql
\ir 54_cdc_ase_cases.sql
\ir 55_cdc_ase_with_sofa.sql
\ir 56_cdc_ase_cohort_final.sql

-- Comparison
DROP TABLE IF EXISTS :results_schema.sepsis_cohort_comparison CASCADE;
\ir 61_create_sepsis_cohort_comparison.sql

-- Reset session tuning
RESET work_mem;
RESET maintenance_work_mem;
RESET max_parallel_workers_per_gather;
RESET temp_buffers;
RESET synchronous_commit;

ANALYZE :results_schema.sofa_hourly;
ANALYZE :results_schema.cdc_ase_cohort_final;
ANALYZE :results_schema.sepsis_cohort_comparison;
