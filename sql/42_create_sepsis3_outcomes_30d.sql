-- 42_create_sepsis3_outcomes_30d.sql
-- Link Sepsis-3 episodes to 30-day mortality, Hospital LOS, and ICU LOS
-- MGH version 2026-05-01 - OPTIMIZED

DROP TABLE IF EXISTS :results_schema.sepsis3_outcomes_30d CASCADE;

CREATE TABLE :results_schema.sepsis3_outcomes_30d AS
WITH sepsis_visit_link AS (
  -- Link the infection strictly to the visit it occurred in, 
  -- using DISTINCT ON to prevent fan-out from overlapping OMOP visits
  SELECT DISTINCT ON (s.person_id, s.infection_onset)
    s.*,
    v.visit_occurrence_id,
    EXTRACT(EPOCH FROM (v.visit_end_datetime - v.visit_start_datetime))/86400.0 AS hospital_los_days
  FROM :results_schema.sepsis3_enhanced_collapsed s
  LEFT JOIN :cdm_schema.visit_occurrence v 
    ON v.person_id = s.person_id
   AND s.infection_onset >= v.visit_start_datetime 
   AND s.infection_onset <= v.visit_end_datetime
   AND v.visit_concept_id IN (9201, 262) -- inpatient only, drop ED
  ORDER BY s.person_id, s.infection_onset, v.visit_start_datetime
),
icu_aggregated AS (
  -- Sum all ICU days per visit to prevent row duplication from ward transfers
  SELECT 
    visit_occurrence_id,
    SUM(EXTRACT(EPOCH FROM (visit_detail_end_datetime - visit_detail_start_datetime))/86400.0) AS icu_los_days
  FROM :cdm_schema.visit_detail
  WHERE visit_detail_concept_id = 32037
  GROUP BY visit_occurrence_id
)
SELECT
  sv.person_id,
  sv.infection_onset,
  sv.baseline_sofa,
  sv.max_sofa,
  sv.sofa_delta,
  -- Cast infection_onset to DATE to catch same-day deaths
  CASE WHEN d.death_date IS NOT NULL 
        AND d.death_date >= sv.infection_onset::DATE 
        AND d.death_date <= (sv.infection_onset + INTERVAL '30 days')::DATE
       THEN TRUE ELSE FALSE END AS died_30d,
  COALESCE(icu.icu_los_days, 0) AS icu_los_days,
  sv.hospital_los_days
FROM sepsis_visit_link sv
LEFT JOIN :cdm_schema.death d 
  ON d.person_id = sv.person_id
LEFT JOIN icu_aggregated icu 
  ON icu.visit_occurrence_id = sv.visit_occurrence_id;

CREATE INDEX idx_sepsis3_outcomes_pid ON :results_schema.sepsis3_outcomes_30d (person_id);
ANALYZE :results_schema.sepsis3_outcomes_30d;
