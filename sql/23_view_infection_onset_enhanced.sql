-- 23_view_infection_onset_enhanced.sql
-- FIXED: Deduplicate to first infection per hospitalization

DROP VIEW IF EXISTS results_site_a.infection_onset_enhanced CASCADE;

CREATE OR REPLACE VIEW results_site_a.infection_onset_enhanced AS
WITH antibiotic_starts AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        drug_exposure_start_datetime AS abx_start,
        drug_concept_id
    FROM omopcdm.drug_exposure
    WHERE drug_concept_id IN (
        SELECT descendant_concept_id 
        FROM omopcdm.concept_ancestor 
        WHERE ancestor_concept_id = 21602796  -- Antibiotics
    )
),
culture_starts AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        measurement_datetime AS culture_time,
        measurement_concept_id
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (
        SELECT descendant_concept_id 
        FROM omopcdm.concept_ancestor 
        WHERE ancestor_concept_id = 40486635  -- Blood culture
    )
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
