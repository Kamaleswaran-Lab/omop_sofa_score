-- Sepsis-3 outcomes for MGH / any OMOP site
-- Uses omopcdm.death (NOT visit_occurrence.discharged_to_concept_id)
-- MGH has 444k NULL discharges — death table is source of truth

DROP TABLE IF EXISTS {{ results_schema }}.sepsis3_cases_with_outcomes;
CREATE TABLE {{ results_schema }}.sepsis3_cases_with_outcomes AS
WITH episodes AS (
    -- collapse antibiotic-culture pairs to 48h episodes (your 219)
    SELECT DISTINCT ON (person_id, infection_onset)
        person_id,
        infection_onset,
        sepsis_onset,
        baseline_sofa,
        peak_sofa,
        delta_sofa,
        baseline_method
    FROM {{ results_schema }}.sepsis3_cases
    ORDER BY person_id, infection_onset
),
ep48 AS (
    SELECT *,
        SUM(CASE WHEN LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) IS NULL 
                  OR infection_onset - LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) > interval '48 hours'
                 THEN 1 ELSE 0 END) 
        OVER (PARTITION BY person_id ORDER BY infection_onset) AS episode_num
    FROM episodes
),
final_episodes AS (
    SELECT DISTINCT ON (person_id, episode_num) *
    FROM ep48
    ORDER BY person_id, episode_num, infection_onset
)
SELECT
    f.person_id,
    f.infection_onset AS t_sepsis3,
    f.baseline_sofa,
    f.peak_sofa,
    f.delta_sofa,
    -- MGH death: death_type_concept_id = 32817
    d.death_date,
    d.death_type_concept_id,
    -- 30-day mortality (Sepsis-3 standard)
    CASE WHEN d.person_id IS NOT NULL 
          AND d.death_date BETWEEN f.infection_onset::date 
                               AND (f.infection_onset::date + interval '30 days')
         THEN 1 ELSE 0 END AS died_30d,
    -- in-hospital mortality (join to visit)
    CASE WHEN d.person_id IS NOT NULL 
          AND d.death_date BETWEEN v.visit_start_date 
                               AND COALESCE(v.visit_end_date, d.death_date)
         THEN 1 ELSE 0 END AS died_in_hospital,
    v.visit_occurrence_id,
    v.visit_start_date,
    v.visit_end_date
FROM final_episodes f
LEFT JOIN {{ cdm_schema }}.visit_occurrence v
  ON v.person_id = f.person_id
 AND f.infection_onset BETWEEN v.visit_start_datetime AND v.visit_end_datetime
LEFT JOIN {{ cdm_schema }}.death d
  ON d.person_id = f.person_id;
-- Note: do NOT use v.discharged_to_concept_id = 4216643 (MGH = NULL)
