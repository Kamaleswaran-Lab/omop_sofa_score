CREATE OR REPLACE VIEW :results_schema.vasopressors_nee AS
WITH vc AS (SELECT concept_id, nee_factor FROM :results_schema.assumptions WHERE domain='vasopressor')
SELECT de.person_id, de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_datetime,
  COALESCE(
    de.drug_exposure_end_datetime,
    LEAD(COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp))
      OVER (PARTITION BY de.person_id, de.drug_concept_id ORDER BY de.drug_exposure_start_datetime),
    COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) + INTERVAL '4 hours'
  ) AS end_datetime,
  de.drug_concept_id, vc.nee_factor,
  de.quantity -- you'll need this for actual NEE dose
FROM :cdm_schema.drug_exposure de
JOIN vc ON vc.concept_id = de.drug_concept_id
WHERE de.route_concept_id IN (4157765,4112421,4139962); -- IV only, drop IS NULL
