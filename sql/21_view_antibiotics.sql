CREATE OR REPLACE VIEW :results_schema.view_antibiotics AS
SELECT
  de.person_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS drug_exposure_start_datetime,
  de.visit_occurrence_id,
  de.route_concept_id,
  de.drug_exposure_id
FROM :cdm_schema.drug_exposure de
JOIN :results_schema.concept_set_members cs
  ON cs.concept_id = de.drug_concept_id
 AND cs.concept_set_name = 'antibiotic'
WHERE COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) IS NOT NULL;
