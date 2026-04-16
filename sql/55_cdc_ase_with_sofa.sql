-- 55_cdc_ase_with_sofa.sql
-- PURPOSE: Attach SOFA scores to ASE cases

DROP TABLE IF EXISTS omop_cdm.ase_with_sofa CASCADE;
CREATE TABLE omop_cdm.ase_with_sofa AS
SELECT
  ac.*,
  sh.sofa_total,
  sh.sofa_datetime
FROM omop_cdm.ase_cases ac
LEFT JOIN omop_sofa.sofa_hourly sh
  ON sh.person_id = ac.person_id
 AND sh.sofa_datetime BETWEEN ac.infection_onset - INTERVAL '1 day'
                          AND ac.infection_onset + INTERVAL '3 days'
;
