-- 56_cdc_ase_cohort_final.sql
DROP TABLE IF EXISTS :results_schema.ase_cohort_final CASCADE;
CREATE TABLE :results_schema.ase_cohort_final AS
WITH icu AS (
  SELECT DISTINCT vd.person_id, vd.visit_occurrence_id
  FROM :cdm_schema.visit_detail vd
  JOIN :results_schema.assumptions a ON a.domain='icu' AND a.concept_id=vd.visit_detail_concept_id
)
SELECT ac.person_id, ac.visit_occurrence_id, ac.infection_onset,
       vo.visit_start_datetime AS admit_time, vo.visit_end_datetime AS discharge_time,
       MAX(CASE WHEN v.start_datetime BETWEEN ac.infection_onset - INTERVAL '2 days' AND ac.infection_onset + INTERVAL '2 days' THEN 1 ELSE 0 END) AS vasopressor_flag,
       MAX(CASE WHEN vent.start_datetime BETWEEN ac.infection_onset - INTERVAL '2 days' AND ac.infection_onset + INTERVAL '2 days' THEN 1 ELSE 0 END) AS vent_flag,
       MAX(CASE WHEN icu.person_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_flag,
       CASE WHEN vo.discharge_to_concept_id = 4216643 THEN 1 ELSE 0 END AS death_in_hosp
FROM :results_schema.ase_cases ac
JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id = ac.visit_occurrence_id
LEFT JOIN :results_schema.vasopressors_nee v ON v.person_id=ac.person_id
LEFT JOIN :results_schema.ventilation vent ON vent.person_id=ac.person_id
LEFT JOIN icu ON icu.person_id=ac.person_id AND icu.visit_occurrence_id=ac.visit_occurrence_id
GROUP BY ac.person_id, ac.visit_occurrence_id, ac.infection_onset, vo.visit_start_datetime, vo.visit_end_datetime, vo.discharge_to_concept_id;

DROP VIEW IF EXISTS :results_schema.ase_cohort_summary CASCADE;
CREATE VIEW :results_schema.ase_cohort_summary AS
SELECT 'Cohort Summary' AS metric,
       COUNT(*) AS total_episodes,
       COUNT(DISTINCT person_id) AS unique_patients,
       SUM(vasopressor_flag) AS vasopressor_count,
       ROUND(100.0*AVG(vasopressor_flag),1) AS vasopressor_pct,
       SUM(vent_flag) AS vent_count,
       ROUND(100.0*AVG(vent_flag),1) AS vent_pct,
       SUM(icu_flag) AS icu_count,
       ROUND(100.0*AVG(icu_flag),1) AS icu_pct,
       SUM(death_in_hosp) AS deaths_in_hosp
FROM :results_schema.ase_cohort_final;
