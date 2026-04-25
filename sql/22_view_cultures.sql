-- Cultures view - uses ancestor
DROP VIEW IF EXISTS :results_schema.vw_cultures CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_cultures AS
SELECT m.person_id,
       COALESCE(m.measurement_datetime, m.measurement_date::timestamp) AS specimen_datetime,
       m.measurement_concept_id AS specimen_concept_id,
       c.concept_name AS specimen_name,
       m.visit_occurrence_id
FROM :cdm_schema.measurement m
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = m.measurement_concept_id
LEFT JOIN :vocab_schema.concept c ON c.concept_id = m.measurement_concept_id
WHERE ca.ancestor_concept_id = 40486635; -- Microbiology cultures
