-- Fix: Completely rebuilt to generate the specific column schema that your RUN_ALL_cdc_ase.sql script actually queries against, using MGH Death table hierarchy
DROP TABLE IF EXISTS :results_schema.cdc_ase_cohort_final CASCADE;
CREATE TABLE :results_schema.cdc_ase_cohort_final AS
WITH case_sofa AS (
  SELECT person_id, infection_onset, MAX(sofa_total) AS max_sofa_72h
  FROM :results_schema.ase_with_sofa
  GROUP BY person_id, infection_onset
),
icu_stays AS (
  -- Explicit CHoRUS MGH ICU concepts
  SELECT DISTINCT person_id, visit_occurrence_id, visit_detail_start_datetime, visit_detail_end_datetime
  FROM :cdm_schema.visit_detail
  WHERE visit_detail_concept_id IN (2072499989,581383,2072500011,2072500012,2072500018,2072500007,2072500031,2072500010,2072500004)
)
SELECT DISTINCT ON (ac.person_id, ac.infection_onset)
  ac.person_id,
  vo.visit_occurrence_id,
  ac.infection_onset::date AS onset_date,
  ac.infection_onset,
  vo.visit_start_datetime AS admit_time,
  vo.visit_end_datetime AS discharge_time,
  
  -- Onset Type
  CASE WHEN ac.infection_onset - vo.visit_start_datetime < INTERVAL '48 hours' THEN 'community-onset' ELSE 'hospital-onset' END AS onset_type,
  c.concept_name AS visit_type,
  
  -- SOFA Severity
  COALESCE(cs.max_sofa_72h, 0) AS max_sofa_72h,
  CASE 
      WHEN cs.max_sofa_72h <= 2 THEN 'minimal'
      WHEN cs.max_sofa_72h <= 5 THEN 'mild'
      WHEN cs.max_sofa_72h <= 9 THEN 'moderate'
      ELSE 'severe' 
  END AS sofa_severity,
  
  -- Organ Support Flags
  CASE WHEN icu.person_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
  od.vaso_init AS vasopressor_72h,
  od.vent_init AS ventilation_72h,
  GREATEST(CASE WHEN icu.person_id IS NOT NULL THEN 1 ELSE 0 END, od.vaso_init::int, od.vent_init::int) AS organ_support,
  
  -- Outcomes
  CASE WHEN d.death_date BETWEEN vo.visit_start_date AND COALESCE(vo.visit_end_date, d.death_date) THEN 1 ELSE 0 END AS died_in_hospital,
  CASE WHEN d.death_date BETWEEN ac.infection_onset::date AND ac.infection_onset::date + INTERVAL '30 days' THEN 1 ELSE 0 END AS died_30d,
  EXTRACT(EPOCH FROM (vo.visit_end_datetime - vo.visit_start_datetime))/86400.0 AS hospital_los_days

FROM :results_schema.ase_cases ac
LEFT JOIN :cdm_schema.visit_occurrence vo 
  ON vo.person_id = ac.person_id 
 AND ac.infection_onset BETWEEN vo.visit_start_datetime AND vo.visit_end_datetime
LEFT JOIN :vocab_schema.concept c ON c.concept_id = vo.visit_concept_id
LEFT JOIN case_sofa cs ON cs.person_id = ac.person_id AND cs.infection_onset = ac.infection_onset
LEFT JOIN :results_schema.ase_organ_dysfunction od ON od.person_id = ac.person_id AND od.culture_datetime = ac.infection_onset
LEFT JOIN icu_stays icu ON icu.person_id = ac.person_id AND ac.infection_onset BETWEEN icu.visit_detail_start_datetime AND icu.visit_detail_end_datetime
LEFT JOIN :cdm_schema.death d ON d.person_id = ac.person_id;
