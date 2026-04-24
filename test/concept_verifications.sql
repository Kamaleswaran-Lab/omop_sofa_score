-- verification_psql.sql
-- Run: psql -d your_db -f verification_psql.sql -v cdm_schema=omopcdm -v vocab_schema=vocabulary

\echo '=== 1. ROUTE CONCEPTS (critical) ==='
SELECT 
    concept_id,
    concept_name,
    domain_id,
    vocabulary_id,
    standard_concept
FROM :vocab_schema.concept
WHERE concept_id IN (
    4112421,  -- should be Intravenous
    4139566,  -- should be Intravenous bolus
    4156705,  -- should be Intravenous drip
    4132161,  -- should be Oral (you caught this)
    4128794,  -- should be Intramuscular
    45956875, -- should be Topical
    4263686,  -- should be Ophthalmic
    4186834,  -- Inhalation
    4186833,  -- Nasal
    4136280   -- Otic
)
ORDER BY concept_id;

\echo '=== 2. CDC ANTIMICROBIAL ANCESTOR ==='
SELECT concept_id, concept_name 
FROM :vocab_schema.concept 
WHERE concept_id = 21602796;

\echo '=== 3. YOUR CDC TABLE COUNT ==='
SELECT 
    'cdc_ase_antimicrobial_concepts' as table_name,
    COUNT(*) as n_concepts,
    COUNT(DISTINCT concept_id) as unique_ids
FROM results_site_a.cdc_ase_antimicrobial_concepts;

\echo '=== 4. SAMPLE OF CDC CONCEPTS ==='
SELECT c.concept_id, c.concept_name, c.concept_class_id
FROM results_site_a.cdc_ase_antimicrobial_concepts cdc
JOIN :vocab_schema.concept c ON c.concept_id = cdc.concept_id
LIMIT 10;

\echo '=== 5. CHECK YOUR CURRENT view_antibiotics ==='
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT drug_concept_id) as distinct_drugs,
    COUNT(DISTINCT route_concept_id) as distinct_routes
FROM results_site_a.view_antibiotics;

\echo '=== 6. ROUTES CURRENTLY IN YOUR view_antibiotics ==='
SELECT 
    COALESCE(rc.concept_id, 0) as route_id,
    COALESCE(rc.concept_name, 'NULL') as route_name,
    COUNT(*) as n_exposures
FROM results_site_a.view_antibiotics va
LEFT JOIN :vocab_schema.concept rc ON rc.concept_id = va.route_concept_id
GROUP BY 1,2
ORDER BY 3 DESC
LIMIT 15;

\echo '=== 7. BLOOD CULTURE CONCEPTS ==='
SELECT COUNT(*) as n_blood_culture_concepts
FROM results_site_a.cdc_ase_blood_culture_concepts;

\echo '=== 8. HOSPICE CONCEPT AT YOUR SITE ==='
SELECT 
    discharged_to_concept_id,
    c.concept_name,
    COUNT(*) as n_visits
FROM :cdm_schema.visit_occurrence vo
LEFT JOIN :vocab_schema.concept c ON c.concept_id = vo.discharged_to_concept_id
WHERE discharged_to_concept_id IS NOT NULL
GROUP BY 1,2
ORDER BY 3 DESC
LIMIT 10;
