DROP TABLE IF EXISTS :results_schema.sepsis3_outcomes_30d;
CREATE TABLE :results_schema.sepsis3_outcomes_30d AS
WITH c AS (SELECT * FROM :results_schema.sepsis3_enhanced_collapsed)
SELECT c.person_id, c.infection_onset,
  (d.death_date <= c.infection_onset + interval '30 days') AS death_30d,
  (vo.discharged_to_concept_id IN (:hospice_concepts) AND vo.visit_end_date <= c.infection_onset + interval '30 days') AS hospice_30d
FROM c
LEFT JOIN :cdm_schema.death d ON d.person_id=c.person_id
LEFT JOIN :cdm_schema.visit_occurrence vo ON vo.person_id=c.person_id;
