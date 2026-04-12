-- OMOP SOFA v4.4 - Core laboratory measurements
-- FIX #7: Uses ancestor concepts only, no hardcoded LOINCs

DROP VIEW IF EXISTS results.v_labs_core CASCADE;

CREATE VIEW results.v_labs_core AS
SELECT 
    m.person_id,
    m.measurement_datetime,
    m.measurement_concept_id,
    m.value_as_number,
    m.unit_concept_id,
    m.range_low,
    m.range_high,
    ca.ancestor_concept_id,
    CASE ca.ancestor_concept_id
        WHEN 3002647 THEN 'pao2'
        WHEN 3013468 THEN 'fio2'
        WHEN 3016723 THEN 'creatinine'
        WHEN 3024128 THEN 'bilirubin'
        WHEN 3013290 THEN 'platelets'
        WHEN 4065485 THEN 'urine_output'
    END AS lab_type,
    c.concept_name AS lab_name
FROM cdm.measurement m
JOIN vocab.concept_ancestor ca 
    ON ca.descendant_concept_id = m.measurement_concept_id
JOIN vocab.concept c 
    ON c.concept_id = m.measurement_concept_id
WHERE ca.ancestor_concept_id IN (
    3002647,  -- PaO2 (arterial oxygen)
    3013468,  -- FiO2 (fraction inspired oxygen)
    3016723,  -- Creatinine
    3024128,  -- Bilirubin total
    3013290,  -- Platelets
    4065485   -- Urine output
)
AND m.value_as_number IS NOT NULL
AND m.measurement_datetime IS NOT NULL;

COMMENT ON VIEW results.v_labs_core IS 'Core labs for SOFA using OMOP ancestor concepts';

SELECT 'Core labs view created (6 lab types)' AS status;
