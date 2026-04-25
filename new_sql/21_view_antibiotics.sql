-- Antibiotics view - uses assumptions table
DROP VIEW IF EXISTS :results_schema.view_antibiotics CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_antibiotics AS
SELECT
    de.drug_exposure_id,
    de.person_id,
    de.visit_occurrence_id,
    de.drug_concept_id,
    c.concept_name AS drug_name,
    COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS drug_exposure_start_datetime,
    COALESCE(de.drug_exposure_end_datetime, 
             COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) + INTERVAL '1 day') AS drug_exposure_end_datetime,
    de.route_concept_id,
    rc.concept_name AS route_name
FROM :cdm_schema.drug_exposure de
JOIN :results_schema.assumptions a ON a.domain='antibiotic' AND a.concept_id = de.drug_concept_id
LEFT JOIN :vocab_schema.concept c ON c.concept_id = de.drug_concept_id
LEFT JOIN :vocab_schema.concept rc ON rc.concept_id = de.route_concept_id
WHERE COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) < CURRENT_DATE
  AND (de.route_concept_id IS NULL OR de.route_concept_id NOT IN (40549429,4023156,4263689,4057765,4156707)); -- exclude topical etc
