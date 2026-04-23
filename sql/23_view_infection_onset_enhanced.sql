-- v4.5 Enhanced infection onset
-- Implements: 96h culture window, ≥2 distinct abx, or ICU single-abx
-- Output used by sepsis3_enhanced
-- FIXED: removed nested window function (Postgres WindowingError)
DROP VIEW IF EXISTS {{results_schema}}.view_infection_onset_enhanced CASCADE;

CREATE VIEW {{results_schema}}.view_infection_onset_enhanced AS
WITH abx AS (
    SELECT
        person_id,
        drug_exposure_start_datetime AS abx_time,
        drug_concept_id
    FROM {{cdm_schema}}.drug_exposure de
    JOIN {{vocab_schema}}.concept_ancestor ca
      ON ca.descendant_concept_id = de.drug_concept_id
    WHERE ca.ancestor_concept_id IN (21602796) -- Antibacterials (adjust per site)
      AND de.drug_exposure_start_datetime IS NOT NULL
),
abx_courses AS (
    SELECT
        person_id,
        abx_time,
        drug_concept_id,
        SUM(new_course) OVER (PARTITION BY person_id ORDER BY abx_time) AS course_id
    FROM (
        SELECT
            person_id,
            abx_time,
            drug_concept_id,
            CASE
                WHEN LAG(abx_time) OVER (PARTITION BY person_id ORDER BY abx_time) IS NULL
                  OR abx_time - LAG(abx_time) OVER (PARTITION BY person_id ORDER BY abx_time) > INTERVAL '24 hours'
                THEN 1 ELSE 0
            END AS new_course
        FROM abx
    ) sub
),
courses AS (
    SELECT
        person_id,
        MIN(abx_time) AS infection_onset,
        COUNT(DISTINCT drug_concept_id) AS distinct_abx_count,
        DATE_PART('day', MAX(abx_time) - MIN(abx_time)) + 1 AS total_abx_days
    FROM abx_courses
    GROUP BY person_id, course_id
),
cultures AS (
    SELECT
        person_id,
        COALESCE(measurement_datetime, specimen_datetime) AS culture_time
    FROM {{cdm_schema}}.measurement m
    JOIN {{vocab_schema}}.concept_ancestor ca
      ON ca.descendant_concept_id = m.measurement_concept_id
    WHERE ca.ancestor_concept_id = 40484543 -- Blood culture
    UNION
    SELECT person_id, specimen_datetime
    FROM {{cdm_schema}}.specimen s
    JOIN {{vocab_schema}}.concept_ancestor ca
      ON ca.descendant_concept_id = s.specimen_concept_id
    WHERE ca.ancestor_concept_id = 40484543
),
with_flags AS (
    SELECT
        c.*,
        EXISTS (
            SELECT 1 FROM cultures cu
            WHERE cu.person_id = c.person_id
              AND cu.culture_time BETWEEN c.infection_onset - INTERVAL '24 hours'
                                      AND c.infection_onset + INTERVAL '96 hours'
        ) AS has_culture
    FROM courses c
),
typed AS (
    SELECT
        w.*,
        CASE
            WHEN w.has_culture THEN 'culture_positive'
            WHEN w.distinct_abx_count >= 2 THEN 'multi_abx'
            ELSE 'single_abx_icu'
        END AS infection_type
    FROM with_flags w
),
icu_stays AS (
    SELECT
        person_id,
        visit_detail_start_datetime,
        visit_detail_end_datetime
    FROM {{cdm_schema}}.visit_detail
    WHERE visit_detail_concept_id IN (
        2072499989,581383,2072500011,2072500012,
        2072500018,2072500007,2072500031,2072500010,2072500004
    )
)
SELECT
    t.person_id,
    t.infection_onset,
    t.infection_type,
    t.distinct_abx_count,
    t.total_abx_days,
    t.has_culture,
    t.infection_onset - INTERVAL '72 hours' AS baseline_start,
    t.infection_onset + INTERVAL '48 hours' AS organ_dysfunction_end,
    CASE WHEN EXISTS (
        SELECT 1 FROM icu_stays i
        WHERE i.person_id = t.person_id
          AND t.infection_onset BETWEEN i.visit_detail_start_datetime AND i.visit_detail_end_datetime
    ) THEN 1 ELSE 0 END AS icu_onset
FROM typed t
WHERE (t.has_culture
    OR t.distinct_abx_count >= 2
    OR t.infection_type = 'single_abx_icu')
  AND t.infection_onset < CURRENT_DATE;
