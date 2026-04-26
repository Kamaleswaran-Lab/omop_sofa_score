CREATE OR REPLACE VIEW :results_schema.view_infection_onset_enhanced AS
SELECT DISTINCT person_id, LEAST(abx_time, cult_time) AS infection_onset
FROM (SELECT a.person_id, a.drug_exposure_start_datetime AS abx_time, c.specimen_datetime AS cult_time
      FROM :results_schema.view_antibiotics a JOIN :results_schema.view_cultures c USING (person_id)
      WHERE ABS(EXTRACT(EPOCH FROM (a.drug_exposure_start_datetime - c.specimen_datetime))/3600) <=96) t
WHERE LEAST(abx_time, cult_time) < CURRENT_DATE;