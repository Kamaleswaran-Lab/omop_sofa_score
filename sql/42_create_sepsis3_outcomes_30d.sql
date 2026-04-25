-- 30-day outcomes - fixed hospice handling
DROP TABLE IF EXISTS :results_schema.sepsis3_outcomes_30d CASCADE;
CREATE TABLE :results_schema.sepsis3_outcomes_30d AS
WITH base AS (
  SELECT DISTINCT person_id, visit_occurrence_id, infection_onset, max_delta_sofa
  FROM :results_schema.sepsis3_enhanced_collapsed
  JOIN :results_schema.sepsis3_enhanced USING(person_id, infection_onset)
),
deaths AS (
  SELECT b.person_id, b.visit_occurrence_id, MIN(d.death_date) AS death_date
  FROM base b JOIN :cdm_schema.death d ON d.person_id=b.person_id
  WHERE d.death_date BETWEEN b.infection_onset AND b.infection_onset + interval '30 days'
  GROUP BY 1,2
),
hospice AS (
  SELECT b.person_id, b.visit_occurrence_id, MAX(vo.visit_end_date) AS hospice_date
  FROM base b JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id=b.visit_occurrence_id
  WHERE vo.discharged_to_concept_id IN (8546,38003568,38003569)
    AND vo.visit_end_date BETWEEN b.infection_onset AND b.infection_onset + interval '30 days'
  GROUP BY 1,2
)
SELECT b.person_id, b.visit_occurrence_id, b.infection_onset, b.max_delta_sofa,
       (d.death_date IS NOT NULL) AS death_30d,
       (h.hospice_date IS NOT NULL) AS hospice_30d,
       (d.death_date IS NOT NULL OR h.hospice_date IS NOT NULL) AS composite_30d
FROM base b LEFT JOIN deaths d USING(person_id, visit_occurrence_id) LEFT JOIN hospice h USING(person_id, visit_occurrence_id);
