-- 23_view_infection_onset_enhanced.sql
-- CDC ASE infection onset: culture + antibiotic within 72h
-- Uses results_site_a.ase_blood_cultures (already built)

DROP VIEW IF EXISTS {{results_schema}}.infection_onset_enhanced CASCADE;

CREATE OR REPLACE VIEW {{results_schema}}.infection_onset_enhanced AS

WITH antibiotic_starts AS (
    SELECT 
        de.person_id,
        de.visit_occurrence_id,
        de.drug_exposure_start_datetime AS abx_start,
        de.drug_source_value
    FROM {{omop_schema}}.drug_exposure de
    WHERE de.drug_exposure_start_datetime IS NOT NULL
      AND de.visit_occurrence_id IS NOT NULL
      AND (
        -- Broad-spectrum antibiotics per CDC ASE
        LOWER(de.drug_source_value) LIKE '%vancomycin%' 
        OR LOWER(de.drug_source_value) LIKE '%vanco%'
        OR (LOWER(de.drug_source_value) LIKE '%piperacillin%' AND LOWER(de.drug_source_value) LIKE '%tazobactam%')
        OR LOWER(de.drug_source_value) LIKE '%zosyn%'
        OR LOWER(de.drug_source_value) LIKE '%pip-tazo%'
        OR LOWER(de.drug_source_value) LIKE '%cefepime%'
        OR LOWER(de.drug_source_value) LIKE '%meropenem%'
        OR LOWER(de.drug_source_value) LIKE '%imipenem%'
        OR LOWER(de.drug_source_value) LIKE '%ertapenem%'
        OR LOWER(de.drug_source_value) LIKE '%doripenem%'
        OR LOWER(de.drug_source_value) LIKE '%ceftriaxone%'
        OR LOWER(de.drug_source_value) LIKE '%ceftazidime%'
        OR LOWER(de.drug_source_value) LIKE '%aztreonam%'
        OR LOWER(de.drug_source_value) LIKE '%levofloxacin%'
        OR LOWER(de.drug_source_value) LIKE '%ciprofloxacin%'
        OR LOWER(de.drug_source_value) LIKE '%moxifloxacin%'
      )
),

culture_starts AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        culture_datetime AS culture_time
    FROM {{results_schema}}.ase_blood_cultures
    WHERE culture_datetime IS NOT NULL
),

-- Pair antibiotics and cultures within 72 hours
infection_pairs AS (
    SELECT 
        a.person_id,
        a.visit_occurrence_id,
        a.abx_start,
        c.culture_time,
        ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) AS hours_apart
    FROM antibiotic_starts a
    INNER JOIN culture_starts c 
        ON a.person_id = c.person_id 
        AND a.visit_occurrence_id = c.visit_occurrence_id
    WHERE ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time))/3600) <= 72
),

-- Determine infection onset (earlier of the two)
infection_candidates AS (
    SELECT 
        person_id,
        visit_occurrence_id,
        LEAST(abx_start, culture_time) AS infection_onset,
        CASE 
            WHEN abx_start <= culture_time THEN 'antibiotic_first'
            ELSE 'culture_first'
        END AS infection_type,
        abx_start AS antibiotic_start,
        culture_time AS culture_start,
        hours_apart
    FROM infection_pairs
)

-- Take earliest infection per visit
SELECT 
    person_id,
    visit_occurrence_id,
    infection_onset,
    infection_type,
    antibiotic_start,
    culture_start
FROM (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY person_id, visit_occurrence_id 
            ORDER BY infection_onset ASC, hours_apart ASC
        ) AS rn
    FROM infection_candidates
) ranked
WHERE rn = 1;

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_infection_onset_enhanced_person 
ON {{results_schema}}.infection_onset_enhanced(person_id, visit_occurrence_id);
