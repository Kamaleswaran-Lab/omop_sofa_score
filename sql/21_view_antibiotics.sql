-- OMOP SOFA v4.4 - Antibiotics for Sepsis-3

DROP VIEW IF EXISTS results.v_antibiotics CASCADE;

CREATE VIEW results.v_antibiotics AS
SELECT 
    d.person_id,
    d.drug_exposure_start_datetime AS abx_start,
    d.drug_exposure_end_datetime AS abx_end,
    d.drug_concept_id,
    c.concept_name AS antibiotic_name,
    d.route_concept_id,
    r.concept_name AS route_name,
    d.quantity,
    d.days_supply
FROM cdm.drug_exposure d
JOIN vocab.concept_ancestor ca 
    ON ca.descendant_concept_id = d.drug_concept_id
JOIN vocab.concept c 
    ON c.concept_id = d.drug_concept_id
LEFT JOIN vocab.concept r 
    ON r.concept_id = d.route_concept_id
WHERE ca.ancestor_concept_id = 21600381  -- Antibacterial agents
AND d.drug_exposure_start_datetime IS NOT NULL;

COMMENT ON VIEW results.v_antibiotics IS 'Antibiotics for Sepsis-3 infection detection';

SELECT 'Antibiotics view created' AS status;
