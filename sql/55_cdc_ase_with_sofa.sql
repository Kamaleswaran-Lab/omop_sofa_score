-- Fix: Using correct column names total_sofa and charttime
DROP TABLE IF EXISTS :results_schema.ase_with_sofa CASCADE;
CREATE TABLE :results_schema.ase_with_sofa AS
SELECT
  ac.*,
  sh.total_sofa AS sofa_total,
  sh.charttime AS sofa_datetime
FROM :results_schema.ase_cases ac
LEFT JOIN :results_schema.sofa_hourly sh
  ON sh.person_id = ac.person_id
 AND sh.charttime BETWEEN ac.infection_onset - INTERVAL '24 hours'
                      AND ac.infection_onset + INTERVAL '48 hours';
