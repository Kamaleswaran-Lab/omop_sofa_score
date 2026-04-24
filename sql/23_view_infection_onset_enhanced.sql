-- 23_view_infection_onset_enhanced.sql
-- FIXED: Use correct OMOP antibiotic and culture concepts for MGH

DROP VIEW IF EXISTS {{results_schema}}.infection_onset_enhanced CASCADE;

CREATE OR REPLACE VIEW {{results_schema}}.infection_onset_enhanced AS
WITH antibiotic_starts AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        drug_exposure_start_datetime AS abx_start,
        drug_concept_id
    FROM {{omop_schema}}.drug_exposure
    WHERE drug_concept_id IN (
        -- Antibacterial agents (ATC J01) descendants
        SELECT descendant_concept_id 
        FROM {{omop_schema}}.concept_ancestor 
        WHERE ancestor_concept_id = 21602796
        UNION
        -- Fallback: common IV antibiotics if ancestor missing
        SELECT concept_id FROM {{omop_schema}}.concept 
        WHERE concept_id IN (
            19033961, -- Vancomycin
            1713332,  -- Piperacillin-tazobactam
            1513849,  -- Cefepime
            19012507, -- Meropenem
            1713740,  -- Ceftriaxone
            19088382  -- Levofloxacin
        )
    )
    AND drug_exposure_start_datetime IS NOT NULL
),
culture_starts AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        measurement_datetime AS culture_time,
        measurement_concept_id
    FROM {{omop_schema}}.measurement
    WHERE (
        measurement_concept_id IN (
            -- Blood culture descendants
            SELECT descendant_concept_id 
            FROM {{omop_schema}}.concept_ancestor 
            WHERE ancestor_concept_id = 40486635
            UNION
            -- Common culture concept IDs
            SELECT 3008805  -- Blood culture
            UNION SELECT 4106999
            UNION SELECT 4289589
        )
        OR LOWER(measurement_source_value) LIKE '%blood cult%'
        OR LOWER(measurement_source_value) LIKE '%bcx%'
    )
    AND measurement_datetime IS NOT NULL
),
infection_candidates AS (
    SELECT 
        a.person_id,
        a.visit_occurrence_id,
        LEAST(a.abx_start, c.culture_time) AS infection_onset,
        CASE 
            WHEN a.abx_start <= c.culture_time THEN 'antibiotic_first'
            ELSE 'culture_first'
        END AS infection_type,
        a.abx_start AS antibiotic_start,
        c.culture_time AS culture_start
    FROM antibiotic_starts a
    JOIN culture_starts c ON a.person_id = c.person_id 
        AND a.visit_occurrence_id = c.visit_occurrence_id
        AND ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) <= 72
)
-- DEDUPLICATE: keep first infection per visit
SELECT 
    person_id,
    visit_occurrence_id,
    infection_onset,
    infection_type,
    antibiotic_start,
    culture_start
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY person_id, visit_occurrence_id 
            ORDER BY infection_onset
        ) AS rn
    FROM infection_candidates
) ranked
WHERE rn = 1;
