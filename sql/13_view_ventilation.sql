-- Ventilation detection (3 domains)
DROP VIEW IF EXISTS results_site_a.vw_ventilation CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_ventilation AS
SELECT DISTINCT 
    vo.person_id, 
    COALESCE(de.device_exposure_start_datetime, vo.visit_start_datetime) AS charttime, 
    TRUE AS ventilated,
    'device' AS source
FROM omopcdm.device_exposure de
JOIN omopcdm.visit_occurrence vo ON de.visit_occurrence_id = vo.visit_occurrence_id
WHERE de.device_concept_id = 4222965  -- Oxygen equipment - 3,846,770 records
UNION
SELECT DISTINCT 
    po.person_id, 
    po.procedure_datetime AS charttime, 
    TRUE AS ventilated,
    'procedure' AS source
FROM omopcdm.procedure_occurrence po
WHERE po.procedure_concept_id IN (4202832, 42738694)
UNION
SELECT DISTINCT
    m.person_id,
    m.measurement_datetime AS charttime,
    TRUE AS ventilated,
    'measurement' AS source
FROM omopcdm.measurement m
WHERE m.measurement_concept_id IN (21490855, 36303772, 44782827, 4064992)  -- PEEP, mean airway pressure, tidal volume
AND m.value_as_number IS NOT NULL;