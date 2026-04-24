-- 21_view_antibiotics.sql — v4.5.1 CORRECTED
-- Uses CDC ASE antimicrobial concepts with VERIFIED route IDs

DROP VIEW IF EXISTS @results_schema.view_antibiotics CASCADE;

CREATE OR REPLACE VIEW @results_schema.view_antibiotics AS
SELECT
    de.drug_exposure_id,
    de.person_id,
    de.visit_occurrence_id,
    de.drug_concept_id,
    c.concept_name as drug_name,
    de.drug_exposure_start_date,
    de.drug_exposure_start_datetime,
    de.drug_exposure_end_date,
    de.drug_exposure_end_datetime,
    de.route_concept_id,
    rc.concept_name as route_name,
    de.quantity,
    de.days_supply,
    de.visit_detail_id
FROM @cdm_schema.drug_exposure de
INNER JOIN @results_schema.cdc_ase_antimicrobial_concepts cdc
    ON de.drug_concept_id = cdc.concept_id
LEFT JOIN @vocab_schema.concept c ON c.concept_id = de.drug_concept_id
LEFT JOIN @vocab_schema.concept rc ON rc.concept_id = de.route_concept_id
WHERE
    -- VERIFIED systemic routes only
    de.route_concept_id IN (
        4112421, -- Intravenous (VERIFIED)
        4139566, -- Intravenous bolus (VERIFIED)
        4156705, -- Intravenous drip (VERIFIED)
        4132161, -- Oral (VERIFIED - )
        4128794 -- Intramuscular (VERIFIED)
    )
    OR de.route_concept_id IS NULL -- include null routes (many EHRs)
    -- Explicitly exclude non-systemic
    AND COALESCE(de.route_concept_id, 0) NOT IN (
        45956875, -- Topical
        4263686, -- Ophthalmic
        4186834, -- Inhalation
        4186833, -- Nasal
        4136280, -- Otic
        4184015, -- Cutaneous
        4233944 -- Transdermal
    )
    AND de.drug_exposure_start_date < CURRENT_DATE;

COMMENT ON VIEW @results_schema.view_antibiotics IS
'CDC ASE systemic antibiotics. VERIFIED routes: IV(4112421,4139566,4156705), Oral(4132161), IM(4128794). Excludes topical.';
