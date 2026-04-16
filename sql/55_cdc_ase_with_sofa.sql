-- 55_cdc_ase_with_sofa.sql
DROP TABLE IF EXISTS :results_schema.ase_with_sofa CASCADE;
CREATE TABLE :results_schema.ase_with_sofa AS
SELECT ac.*, sh.sofa_total, sh.sofa_datetime
FROM :results_schema.ase_cases ac
LEFT JOIN :results_schema.sofa_hourly sh
  ON sh.person_id=ac.person_id
 AND sh.sofa_datetime BETWEEN ac.infection_onset - INTERVAL '1 day' AND ac.infection_onset + INTERVAL '3 days';
