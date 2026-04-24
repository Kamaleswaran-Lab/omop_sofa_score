-- 23_view_infection_onset_enhanced.sql — v4.5.1 CORRECTED

DROP VIEW IF EXISTS @results_schema.view_infection_onset_enhanced CASCADE;

CREATE OR REPLACE VIEW @results_schema.view_infection_onset_enhanced AS
WITH cultures AS (
    SELECT
        m.person_id,
        m.visit_occurrence_id,
        m.measurement_datetime as culture_datetime,
        m.measurement_date as culture_date
    FROM @cdm_schema.measurement m
    INNER JOIN @results_schema.cdc_ase_blood_culture_concepts bcc
        ON m.measurement_concept_id = bcc.concept_id
    WHERE m.measurement_datetime < CURRENT_DATE
    AND m.measurement_datetime IS NOT NULL
),
abx AS (
    SELECT
        person_id,
        visit_occurrence_id,
        drug_exposure_start_datetime as abx_datetime,
        drug_exposure_start_date as abx_date,
        drug_concept_id,
        route_concept_id
    FROM @results_schema.view_antibiotics
    WHERE drug_exposure_start_datetime IS NOT NULL
),
paired AS (
    SELECT
        c.person_id,
        c.visit_occurrence_id,
        c.culture_datetime,
        a.abx_datetime,
        LEAST(a.abx_datetime, c.culture_datetime) as infection_onset,
        ABS(EXTRACT(EPOCH FROM (a.abx_datetime - c.culture_datetime))/3600) as hours_diff
    FROM cultures c
    JOIN abx a
        ON c.person_id = a.person_id
        AND c.visit_occurrence_id = a.visit_occurrence_id
        AND a.abx_datetime BETWEEN c.culture_datetime - INTERVAL '48 hours'
                               AND c.culture_datetime + INTERVAL '96 hours'
),
multi_abx AS (
    SELECT
        a1.person_id,
        a1.visit_occurrence_id,
        a1.abx_datetime as infection_onset
    FROM abx a1
    JOIN abx a2 ON a1.person_id = a2.person_id
        AND a1.visit_occurrence_id = a2.visit_occurrence_id
        AND a2.abx_datetime > a1.abx_datetime
        AND a2.abx_datetime <= a1.abx_datetime + INTERVAL '48 hours'
        AND a2.drug_concept_id!= a1.drug_concept_id
    WHERE NOT EXISTS (
        SELECT 1 FROM paired p
        WHERE p.person_id = a1.person_id
        AND p.visit_occurrence_id = a1.visit_occurrence_id
        AND ABS(EXTRACT(EPOCH FROM (p.infection_onset - a1.abx_datetime))/3600) < 48
    )
    GROUP BY a1.person_id, a1.visit_occurrence_id, a1.abx_datetime
)
SELECT DISTINCT ON (person_id, visit_occurrence_id, infection_onset)
    person_id,
    visit_occurrence_id,
    infection_onset,
    CASE
        WHEN source = 'paired' THEN 'culture+abx'
        ELSE 'multi_abx'
    END as onset_type
FROM (
    SELECT person_id, visit_occurrence_id, infection_onset, 'paired' FROM paired
    UNION ALL
    SELECT person_id, visit_occurrence_id, infection_onset, 'multi' FROM multi_abx
) all_onsets
WHERE infection_onset < CURRENT_DATE
ORDER BY person_id, visit_occurrence_id, infection_onset;
