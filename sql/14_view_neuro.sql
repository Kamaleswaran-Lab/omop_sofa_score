-- Neurological assessments
DROP VIEW IF EXISTS :results_schema.vw_neuro CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_neuro AS
SELECT 
    m.person_id,
    m.measurement_datetime AS charttime,
    MAX(CASE WHEN m.measurement_concept_id IN (4093836, 3016335, 3009094, 3008223) 
        THEN m.value_as_number END) AS gcs_total,
    MAX(CASE WHEN m.measurement_concept_id = 36684829 
        THEN m.value_as_number END) AS rass_score
FROM :cdm_schema.measurement m
WHERE m.measurement_concept_id IN (4093836, 3016335, 3009094, 3008223, 36684829)
GROUP BY m.person_id, m.measurement_datetime;
