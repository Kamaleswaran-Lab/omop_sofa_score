-- 21_view_antibiotics_MGH.sql
DROP VIEW IF EXISTS results_site_a.view_antibiotics CASCADE;

CREATE OR REPLACE VIEW results_site_a.view_antibiotics AS
SELECT
    de.drug_exposure_id,
    de.person_id,
    de.visit_occurrence_id,
    de.drug_concept_id,
    c.concept_name as drug_name,
    de.drug_exposure_start_datetime,
    de.drug_exposure_end_datetime,
    de.route_concept_id,
    rc.concept_name as route_name
FROM omopcdm.drug_exposure de
INNER JOIN results_site_a.cdc_ase_antimicrobial_concepts cdc
    ON de.drug_concept_id = cdc.concept_id
LEFT JOIN vocabulary.concept c ON c.concept_id = de.drug_concept_id
LEFT JOIN vocabulary.concept rc ON rc.concept_id = de.route_concept_id
WHERE
    -- Include systemic routes + NULL + enteral tubes
    (de.route_concept_id IS NULL 
     OR de.route_concept_id IN (
        4171047, -- Intravenous
        4132161, -- Oral
        4302612, -- Intramuscular
        4132254, -- Gastrostomy
        4132711, -- Nasogastric
        4133177, -- Jejunostomy
        4303795, -- Orogastric
        4305834  -- Nasojejunal
     ))
    -- Explicitly EXCLUDE non-systemic (from your data)
    AND COALESCE(de.route_concept_id, 0) NOT IN (
        40549429, -- Ocular (13,478 rows)
        4023156,  -- Otic
        4263689,  -- Topical
        4057765,  -- Vaginal
        4156707   -- Intrapleural
    )
    AND de.drug_exposure_start_datetime < CURRENT_DATE;
