-- 12_view_vasopressors_nee.sql
-- FIX: keep NULL end times, allow NULL routes, use assumptions table

DROP VIEW IF EXISTS :results_schema.vasopressors_nee CASCADE;
CREATE OR REPLACE VIEW :results_schema.vasopressors_nee AS
WITH vasopressor_concepts AS (
  SELECT concept_id, nee_factor FROM :results_schema.assumptions WHERE domain = 'vasopressor'
)
SELECT
  de.person_id,
  de.visit_occurrence_id,
  de.visit_detail_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_datetime,
  COALESCE(
    de.drug_exposure_end_datetime,
    CASE WHEN de.days_supply IS NOT NULL 
         THEN COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) + (de.days_supply * INTERVAL '1 day')
         ELSE COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) + INTERVAL '1 hour'
    END
  ) AS end_datetime,
  de.drug_concept_id,
  vc.nee_factor
FROM :cdm_schema.drug_exposure de
JOIN vasopressor_concepts vc ON vc.concept_id = de.drug_concept_id
WHERE (de.route_concept_id IN (4157765, 4112421, 4139962) OR de.route_concept_id IS NULL);
