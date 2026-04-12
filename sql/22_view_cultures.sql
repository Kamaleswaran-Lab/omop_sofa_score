-- OMOP SOFA v4.4 - Microbiological cultures

DROP VIEW IF EXISTS results.v_cultures CASCADE;

CREATE VIEW results.v_cultures AS
SELECT 
    m.person_id,
    m.measurement_datetime AS culture_time,
    m.measurement_concept_id,
    c.concept_name AS culture_type,
    m.value_source_value,
    m.value_as_string,
    -- Specimen type
    m.measurement_type_concept_id
FROM cdm.measurement m
JOIN vocab.concept_ancestor ca 
    ON ca.descendant_concept_id = m.measurement_concept_id
JOIN vocab.concept c 
    ON c.concept_id = m.measurement_concept_id
WHERE ca.ancestor_concept_id = 4046263  -- Microbiology cultures
AND m.measurement_datetime IS NOT NULL;

COMMENT ON VIEW results.v_cultures IS 'Microbiological cultures for Sepsis-3';

SELECT 'Cultures view created' AS status;
