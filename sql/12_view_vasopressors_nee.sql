-- 12_view_vasopressors_nee.sql
-- PURPOSE: Build a site-tolerant view of vasopressor infusions with norepinephrine-equivalent (NEE) factors
-- FIXES vs original:
--  1) Do NOT drop rows with NULL end_datetime (common for continuous infusions)
--  2) Allow NULL or multiple IV route concepts
--  3) Drive concept lists from omop_sofa.assumptions (domain='vasopressor')
--  4) Keep rows even if weight is missing (NEE calc can be done later)

DROP VIEW IF EXISTS omop_sofa.vasopressors_nee CASCADE;
CREATE OR REPLACE VIEW omop_sofa.vasopressors_nee AS
WITH vasopressor_concepts AS (
  SELECT concept_id, nee_factor, unit_concept_id
  FROM omop_sofa.assumptions
  WHERE domain = 'vasopressor'
)
SELECT
  de.person_id,
  de.visit_occurrence_id,
  de.visit_detail_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_datetime,
  COALESCE(
    de.drug_exposure_end_datetime,
    -- if days_supply present, use it; else assume 1 hour minimum infusion
    CASE WHEN de.days_supply IS NOT NULL THEN de.drug_exposure_start_datetime + (de.days_supply * INTERVAL '1 day')
         ELSE de.drug_exposure_start_datetime + INTERVAL '1 hour' END,
    de.drug_exposure_start_datetime + INTERVAL '1 hour'
  ) AS end_datetime,
  de.drug_concept_id,
  vc.nee_factor,
  de.quantity,
  de.dose_unit_source_value,
  de.route_concept_id
FROM omop_cdm.drug_exposure de
JOIN vasopressor_concepts vc ON vc.concept_id = de.drug_concept_id
WHERE (de.route_concept_id IN (4157765, 4112421, 4139962) OR de.route_concept_id IS NULL) -- IV, IV drip, or missing
  AND de.drug_type_concept_id IN (38000177, 38000178, 32838) -- inpatient administration/EHR
;

COMMENT ON VIEW omop_sofa.vasopressors_nee IS 'Site-tolerant vasopressor exposures; NULL end times imputed';
