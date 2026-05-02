-- 50_cdc_ase_parameters.sql
-- Site A parameters to match enhanced pipeline

DROP TABLE IF EXISTS :results_schema.cdc_ase_parameters;
CREATE TABLE :results_schema.cdc_ase_parameters AS
SELECT
  96 AS culture_window_hours,
  4 AS qad_min_days,
  1 AS qad_max_gap_days,
  2 AS sofa_threshold;
