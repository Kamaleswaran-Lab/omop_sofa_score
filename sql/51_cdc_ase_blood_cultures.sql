-- 51_cdc_ase_blood_cultures.sql
-- Site A edit: use infection_onset_enhanced instead of strict blood culture

DROP TABLE IF EXISTS {{results_schema}}.cdc_ase_cultures CASCADE;
CREATE TABLE {{results_schema}}.cdc_ase_cultures AS
SELECT
  person_id,
  visit_occurrence_id,
  infection_onset AS culture_time,
  culture_start,
  antibiotic_start,
  culture_site
FROM {{results_schema}}.view_infection_onset_enhanced
WHERE culture_start IS NOT NULL
  AND antibiotic_start IS NOT NULL
  AND ABS(EXTRACT(EPOCH FROM (antibiotic_start - culture_start))/3600) <= 96;
