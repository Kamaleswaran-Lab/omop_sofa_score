-- v4.5 30-day outcomes with hospice
DROP TABLE IF EXISTS {{results_schema}}.sepsis3_outcomes_30d CASCADE;

CREATE TABLE {{results_schema}}.sepsis3_outcomes_30d AS
WITH first_episode AS (
    SELECT
        person_id,
        MIN(infection_onset) AS first_onset,
        MIN(baseline_sofa) AS baseline_sofa,
        MAX(peak_sofa) AS peak_sofa,
        MAX(delta_sofa) AS max_delta_sofa,
        COUNT(*) AS total_episodes
    FROM {{results_schema}}.sepsis3_enhanced_collapsed
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
    JOIN {{cdm_schema}}.visit_occurrence vo
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
    -- 30-day EHR death
    CASE WHEN d.death_date BETWEEN f.first_onset::date
                              AND f.first_onset::date + INTERVAL '30 days'
         THEN 1 ELSE 0 END AS death_30d,
    -- 30-day hospice (MGH: 8546 = Hospice)
    CASE WHEN ia.discharged_to_concept_id = 8546
          AND ia.visit_end_date BETWEEN f.first_onset::date
                                   AND f.first_onset::date + INTERVAL '30 days'
         THEN 1 ELSE 0 END AS hospice_30d,
    -- COMPOSITE (keep 30 days as requested)
    CASE WHEN (d.death_date BETWEEN f.first_onset::date AND f.first_onset::date + INTERVAL '30 days')
           OR (ia.discharged_to_concept_id = 8546
               AND ia.visit_end_date BETWEEN f.first_onset::date AND f.first_onset::date + INTERVAL '30 days')
         THEN 1 ELSE 0 END AS death_or_hospice_30d,
    ia.discharged_to_concept_id,
    c.concept_name AS discharge_disposition
FROM first_episode f
LEFT JOIN {{cdm_schema}}.death d ON d.person_id = f.person_id
LEFT JOIN index_admission ia ON ia.person_id = f.person_id
LEFT JOIN {{vocab_schema}}.concept c ON c.concept_id = ia.discharged_to_concept_id;

CREATE INDEX idx_outcomes_30d ON {{results_schema}}.sepsis3_outcomes_30d(person_id);
