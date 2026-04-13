-- Cultures for sepsis detection
DROP VIEW IF EXISTS results_site_a.vw_cultures CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_cultures AS
SELECT 
    s.person_id,
    s.specimen_datetime,
    s.specimen_concept_id,
    c.concept_name AS specimen_name
FROM omopcdm.specimen s
LEFT JOIN vocabulary.concept c ON s.specimen_concept_id = c.concept_id
WHERE s.specimen_concept_id IN (
    4046263, 4299649, 4189544, 4098207, 
    4029193, 4015188, 4296650
);