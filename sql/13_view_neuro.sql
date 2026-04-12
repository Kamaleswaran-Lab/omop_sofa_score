-- OMOP SOFA v4.4 - Neurological assessment
-- FIX #4: GCS with RASS, no forced verbal=1

DROP VIEW IF EXISTS results.v_neuro_assessment CASCADE;

CREATE VIEW results.v_neuro_assessment AS
SELECT
    o.person_id,
    o.observation_datetime,
    
    -- GCS Total
    MAX(CASE 
        WHEN ca.ancestor_concept_id = 4253928 
        THEN o.value_as_number 
    END) AS gcs_total,
    
    -- GCS Components
    MAX(CASE WHEN o.observation_concept_id = 4262885 THEN o.value_as_number END) AS gcs_eye,
    MAX(CASE WHEN o.observation_concept_id = 4262886 THEN o.value_as_number END) AS gcs_motor,
    MAX(CASE WHEN o.observation_concept_id = 4262887 THEN o.value_as_number END) AS gcs_verbal,
    
    -- RASS score (for sedation assessment)
    MAX(CASE 
        WHEN ca.ancestor_concept_id = 40488434 
        THEN o.value_as_number 
    END) AS rass_score,
    
    -- Intubation status
    MAX(CASE 
        WHEN o.observation_concept_id = 4230167 
        THEN o.value_as_number 
    END) AS intubated_flag,
    
    -- CAM-ICU (delirium)
    MAX(CASE 
        WHEN o.observation_concept_id = 40482843 
        THEN o.value_as_number 
    END) AS cam_icu

FROM cdm.observation o
LEFT JOIN vocab.concept_ancestor ca 
    ON ca.descendant_concept_id = o.observation_concept_id
WHERE 
    ca.ancestor_concept_id IN (4253928, 40488434)  -- GCS and RASS
    OR o.observation_concept_id IN (4262885, 4262886, 4262887, 4230167, 40482843)
GROUP BY o.person_id, o.observation_datetime
HAVING MAX(CASE WHEN ca.ancestor_concept_id = 4253928 THEN o.value_as_number END) IS NOT NULL
    OR MAX(CASE WHEN ca.ancestor_concept_id = 40488434 THEN o.value_as_number END) IS NOT NULL;

COMMENT ON VIEW results.v_neuro_assessment IS 'GCS and RASS for neuro SOFA - no forced verbal';

SELECT 'Neuro assessment view created (FIX #4)' AS status;
