DROP TABLE IF EXISTS :results_schema.ase_parameters CASCADE;
CREATE TABLE :results_schema.ase_parameters AS
SELECT
  2 AS infection_window_days_before,
  2 AS infection_window_days_after,
  4 AS qad_min_days,
  1 AS qad_max_gap_days;
