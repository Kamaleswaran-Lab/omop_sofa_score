-- 51_cdc_ase_blood_cultures.sql
-- CDC ASE presumed infection anchor from the canonical infection-onset view.

DROP TABLE IF EXISTS :results_schema.cdc_ase_cultures CASCADE;
CREATE TABLE :results_schema.cdc_ase_cultures AS
SELECT
  person_id,
  visit_occurrence_id,
  culture_time,
  culture_time AS culture_datetime,
  culture_time AS culture_start,
  antibiotic_time AS antibiotic_start,
  'culture'::text AS culture_site
FROM :results_schema.view_infection_onset
WHERE culture_time IS NOT NULL
  AND antibiotic_time IS NOT NULL
  AND ABS(EXTRACT(EPOCH FROM (antibiotic_time - culture_time))/3600) <= (
    SELECT culture_window_hours FROM :results_schema.cdc_ase_parameters
  );
