-- OMOP SOFA v4.4 - Vasopressors with NEE
-- FIX #1: Vasopressin INCLUDED (was excluded in v3.5)
-- FIX #8: Explicit unit normalization

DROP VIEW IF EXISTS results.v_vasopressors_nee CASCADE;

CREATE VIEW results.v_vasopressors_nee AS
SELECT 
    d.person_id,
    d.drug_exposure_start_datetime,
    d.drug_exposure_end_datetime,
    d.drug_concept_id,
    c.concept_name AS drug_name,
    d.quantity AS dose_raw,
    d.dose_unit_concept_id,
    u.concept_name AS unit_name,
    
    -- Get patient weight for normalization
    w.weight_kg,
    
    -- Normalize dose to mcg/kg/min (or U/min for vasopressin)
    CASE 
        WHEN d.dose_unit_concept_id = 8749 AND w.weight_kg IS NOT NULL 
            THEN d.quantity / w.weight_kg  -- mcg/min to mcg/kg/min
        WHEN d.dose_unit_concept_id = 8750 
            THEN d.quantity  -- already mcg/kg/min
        WHEN d.dose_unit_concept_id = 4118123 
            THEN d.quantity  -- U/min for vasopressin, keep as is
        WHEN d.dose_unit_concept_id = 9655
            THEN d.quantity * 1000 / NULLIF(w.weight_kg, 0)  -- mg/min to mcg/kg/min
        ELSE d.quantity
    END AS dose_normalized,
    
    -- NEE conversion factors (FIX #1: vasopressin now included)
    CASE d.drug_concept_id
        WHEN 4328749 THEN 1.0   -- norepinephrine
        WHEN 1338005 THEN 1.0   -- epinephrine
        WHEN 1360635 THEN 2.5   -- VASOPRESSIN - FIX: was excluded in v3.5
        WHEN 1335616 THEN 0.1   -- phenylephrine
        WHEN 1319998 THEN 0.01  -- dopamine
        ELSE 0
    END AS nee_factor,
    
    -- Calculate NEE contribution
    (CASE 
        WHEN d.dose_unit_concept_id = 8749 AND w.weight_kg IS NOT NULL 
            THEN d.quantity / w.weight_kg
        WHEN d.dose_unit_concept_id = 8750 
            THEN d.quantity
        WHEN d.dose_unit_concept_id = 4118123 
            THEN d.quantity
        ELSE d.quantity
    END) * 
    CASE d.drug_concept_id
        WHEN 4328749 THEN 1.0
        WHEN 1338005 THEN 1.0
        WHEN 1360635 THEN 2.5
        WHEN 1335616 THEN 0.1
        WHEN 1319998 THEN 0.01
        ELSE 0
    END AS nee_contribution,
    
    -- Flags
    CASE WHEN d.drug_concept_id = 1360635 THEN TRUE ELSE FALSE END AS is_vasopressin,
    CASE WHEN d.drug_concept_id = 4328749 THEN TRUE ELSE FALSE END AS is_norepinephrine

FROM cdm.drug_exposure d
JOIN vocab.concept c ON c.concept_id = d.drug_concept_id
LEFT JOIN vocab.concept u ON u.concept_id = d.dose_unit_concept_id
LEFT JOIN (
    SELECT 
        person_id, 
        AVG(value_as_number) AS weight_kg
    FROM cdm.measurement 
    WHERE measurement_concept_id = 3013762  -- body weight
        AND value_as_number BETWEEN 20 AND 300  -- valid range
    GROUP BY person_id
) w ON w.person_id = d.person_id
WHERE d.drug_concept_id IN (
    4328749,  -- norepinephrine
    1338005,  -- epinephrine
    1360635,  -- vasopressin (FIX #1: now included)
    1335616,  -- phenylephrine
    1319998   -- dopamine
)
AND d.quantity > 0
AND d.drug_exposure_start_datetime IS NOT NULL;

COMMENT ON VIEW results.v_vasopressors_nee IS 'Vasopressors with NEE - vasopressin INCLUDED at 2.5x';

SELECT 'Vasopressors view created - vasopressin INCLUDED (FIX #1)' AS status;
