-- OMOP SOFA v4.4 - Ventilation detection
-- FIX #9: Multi-domain detection (device + procedure + visit)

DROP VIEW IF EXISTS results.v_ventilation CASCADE;

CREATE VIEW results.v_ventilation AS

-- Method 1: Device exposure (most reliable)
SELECT 
    person_id,
    device_exposure_start_datetime AS start_time,
    COALESCE(
        device_exposure_end_datetime, 
        device_exposure_start_datetime + INTERVAL '4 hours'
    ) AS end_time,
    'device_exposure' AS source,
    device_concept_id,
    d.concept_name AS device_name
FROM cdm.device_exposure de
JOIN vocab.concept d ON d.concept_id = de.device_concept_id
WHERE de.device_concept_id IN (
    SELECT descendant_concept_id 
    FROM vocab.concept_ancestor 
    WHERE ancestor_concept_id = 45768131  -- Mechanical ventilation
)

UNION ALL

-- Method 2: Procedure occurrence
SELECT 
    person_id,
    procedure_datetime AS start_time,
    procedure_datetime + INTERVAL '2 hours' AS end_time,
    'procedure_occurrence' AS source,
    procedure_concept_id,
    p.concept_name AS device_name
FROM cdm.procedure_occurrence po
JOIN vocab.concept p ON p.concept_id = po.procedure_concept_id
WHERE po.procedure_concept_id IN (
    SELECT descendant_concept_id 
    FROM vocab.concept_ancestor 
    WHERE ancestor_concept_id = 4302207  -- Ventilation procedures
)

UNION ALL

-- Method 3: Visit detail (ICU stays often imply ventilation)
SELECT 
    vd.person_id,
    vd.visit_detail_start_datetime AS start_time,
    vd.visit_detail_end_datetime AS end_time,
    'visit_detail' AS source,
    NULL::BIGINT AS device_concept_id,
    'ICU stay' AS device_name
FROM cdm.visit_detail vd
WHERE vd.visit_detail_concept_id = 32037  -- ICU
AND vd.visit_detail_start_datetime IS NOT NULL;

COMMENT ON VIEW results.v_ventilation IS 'Ventilation from 3 OMOP domains';

SELECT 'Ventilation view created (3 domains)' AS status;
