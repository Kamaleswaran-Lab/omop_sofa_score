-- 50_cdc_ase_parameters.sql
-- PURPOSE: Define CDC ASE windows and reference tables
-- FIX: keep timestamps, not dates

DROP TABLE IF EXISTS omop_sofa.ase_parameters CASCADE;
CREATE TABLE omop_sofa.ase_parameters AS
SELECT
  2 AS infection_window_days_before,
  2 AS infection_window_days_after,
  4 AS qad_min_days,
  1 AS qad_max_gap_days
;

COMMENT ON TABLE omop_sofa.ase_parameters IS 'CDC ASE timing parameters';
