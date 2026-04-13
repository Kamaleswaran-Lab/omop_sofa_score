-- 42_create_sepsis3_outcomes_30d.sql - v4.5  FIXED
-- Fixes: removes Jinja, uses  hospice 8546, uses discharged_to_concept_id

DROP TABLE IF EXISTS results_site_a.sepsis3_outcomes_30d CASCADE;

CREATE TABLE results_site_a.sepsis3_outcomes_30d AS
WITH first_episode AS (
    SELECT
        person_id,
        MIN(infection_onset) AS first_onset,
        MIN(baseline_sofa) AS baseline_sofa,
        MAX(peak_sofa) AS peak_sofa,
        MAX(delta_sofa) AS max_delta_sofa,
        COUNT(*) AS total_episodes
    FROM results_site_a.sepsis3_enhanced_collapsed
    WHERE icu_onset = 1
    GROUP BY person_id
),
index_admission AS (
    SELECT DISTINCT ON (f.person_id)
        f.person_id,
        vo.visit_occurrence_id,
        vo.visit_end_date,
        vo.discharged_to_concept_id
    FROM first_episode f
    JOIN omopcdm.visit_occurrence vo
      ON vo.person_id = f.person_id
     AND f.first_onset BETWEEN vo.visit_start_datetime AND vo.visit_end_datetime
    ORDER BY f.person_id, vo.visit_start_datetime
)
SELECT
    f.person_id,
    f.first_onset,
    f.baseline_sofa,
    f.peak_sofa,
    f.max_delta_sofa,
    f.total_episodes,
    d.death_date,
    CASE WHEN d.death_date BETWEEN f.first_onset::date 
                              AND f.first_onset::date + INTERVAL '30 days'
         THEN 1 ELSE 0 END AS death_30d,
    CASE WHEN ia.discharged_to_concept_id = 8546
          AND ia.visit_end_date BETWEEN f.first_onset::date
                                   AND f.first_onset::date + INTERVAL '30 days'
         THEN 1 ELSE 0 END AS hospice_30d,
    CASE WHEN (d.death_date BETWEEN f.first_onset::date AND f.first_onset::date + INTERVAL '30 days')
           OR (ia.discharged_to_concept_id = 8546
               AND ia.visit_end_date BETWEEN f.first_onset::date AND f.first_onset::date + INTERVAL '30 days')
         THEN 1 ELSE 0 END AS death_or_hospice_30d,
    ia.discharged_to_concept_id,
    c.concept_name AS discharge_disposition
FROM first_episode f
LEFT JOIN omopcdm.death d ON d.person_id = f.person_id
LEFT JOIN index_admission ia ON ia.person_id = f.person_id
LEFT JOIN vocabulary.concept c ON c.concept_id = ia.discharged_to_concept_id;

CREATE INDEX idx_sepsis3_outcomes_30d_person ON results_site_a.sepsis3_outcomes_30d(person_id);

-- Verify - should return 1052 | 73 | 14 | 77 | 7.3
SELECT COUNT(*) AS patients,
       SUM(death_30d) AS deaths_30d,
       SUM(hospice_30d) AS hospice_30d,
       SUM(death_or_hospice_30d) AS composite_30d,
       ROUND(100.0*SUM(death_or_hospice_30d)/COUNT(*),1) AS composite_pct
FROM results_site_a.sepsis3_outcomes_30d;
