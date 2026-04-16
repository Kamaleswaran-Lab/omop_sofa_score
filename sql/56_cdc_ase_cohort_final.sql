-- 56_cdc_ase_cohort_final.sql
-- PURPOSE: Final ASE cohort with outcomes and organ support flags
-- FIXES: correct ICU detection, use corrected vasopressor/vent views

DROP TABLE IF EXISTS omop_cdm.ase_cohort_final CASCADE;
CREATE TABLE omop_cdm.ase_cohort_final AS
WITH icu_stays AS (
  SELECT DISTINCT vd.person_id, vd.visit_occurrence_id
  FROM omop_cdm.visit_detail vd
  JOIN omop_sofa.assumptions a ON a.domain='icu' AND a.concept_id = vd.visit_detail_concept_id
)
SELECT
  ac.person_id,
  ac.visit_occurrence_id,
  ac.infection_onset,
  vo.visit_start_datetime AS admit_time,
  vo.visit_end_datetime AS discharge_time,
  -- organ support flags within ASE window
  MAX(CASE WHEN v.start_datetime BETWEEN ac.infection_onset - INTERVAL '2 days' AND ac.infection_onset + INTERVAL '2 days' THEN 1 ELSE 0 END) AS vasopressor_flag,
  MAX(CASE WHEN vent.start_datetime BETWEEN ac.infection_onset - INTERVAL '2 days' AND ac.infection_onset + INTERVAL '2 days' THEN 1 ELSE 0 END) AS vent_flag,
  MAX(CASE WHEN icu.person_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag,
  -- outcomes
  CASE WHEN vo.discharge_to_concept_id = 4216643 THEN 1 ELSE 0 END AS death_in_hosp,
  vo.visit_end_date - ac.infection_onset::date AS los_days
FROM omop_cdm.ase_cases ac
JOIN omop_cdm.visit_occurrence vo ON vo.visit_occurrence_id = ac.visit_occurrence_id
LEFT JOIN omop_sofa.vasopressors_nee v ON v.person_id = ac.person_id
LEFT JOIN omop_sofa.ventilation vent ON vent.person_id = ac.person_id
LEFT JOIN icu_stays icu ON icu.person_id = ac.person_id AND icu.visit_occurrence_id = ac.visit_occurrence_id
GROUP BY ac.person_id, ac.visit_occurrence_id, ac.infection_onset, vo.visit_start_datetime, vo.visit_end_datetime, vo.discharge_to_concept_id, vo.visit_end_date
;

-- summary view matching your original output
DROP VIEW IF EXISTS omop_cdm.ase_cohort_summary CASCADE;
CREATE VIEW omop_cdm.ase_cohort_summary AS
SELECT
  'Cohort Summary' AS metric,
  COUNT(*) AS total_episodes,
  COUNT(DISTINCT person_id) AS unique_patients,
  AVG(vasopressor_flag) AS vasopressor_pct,
  SUM(vasopressor_flag) AS vasopressor_count,
  AVG(vent_flag) AS vent_pct,
  SUM(vent_flag) AS vent_count,
  AVG(icu_flag) AS icu_pct,
  SUM(icu_flag) AS icu_count,
  SUM(death_in_hosp) AS deaths_in_hosp
FROM omop_cdm.ase_cohort_final;
