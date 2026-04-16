-- 54_cdc_ase_cases.sql
-- Final CDC ASE cases - INCLUDES ICU
-- Fixed: removed restrictive visit_concept_id filter that excluded ICU

DROP TABLE IF EXISTS :results_schema.cdc_ase_cases;

CREATE TABLE :results_schema.cdc_ase_cases AS

WITH pi AS (
    SELECT * 
    FROM :results_schema.cdc_ase_presumed_infection
),

od AS (
    SELECT 
        person_id, 
        visit_occurrence_id, 
        culture_date,
        MIN(event_date) AS first_od_date,
        STRING_AGG(DISTINCT od_type, ',') AS od_types
    FROM :results_schema.cdc_ase_organ_dysfunction
    GROUP BY 1,2,3
),

joined AS (
    SELECT
        pi.person_id,
        pi.visit_occurrence_id,
        pi.culture_date,
        pi.first_qad_date,
        od.first_od_date,
        LEAST(pi.culture_date, pi.first_qad_date, od.first_od_date) AS onset_date,
        pi.qad_count,
        od.od_types
    FROM pi
    JOIN od USING (person_id, visit_occurrence_id, culture_date)
),

final AS (
    SELECT
        j.*,
        vo.visit_start_date,
        vo.visit_end_date,
        vo.visit_concept_id,
        c.concept_name AS visit_type,
        (j.onset_date - vo.visit_start_date + 1) AS hospital_day_onset,
        CASE 
            WHEN (j.onset_date - vo.visit_start_date + 1) <= 2 
            THEN 'community-onset' 
            ELSE 'hospital-onset' 
        END AS onset_type,
        EXTRACT(YEAR FROM vo.visit_start_date) AS year
    FROM joined j
    JOIN :cdm_schema.visit_occurrence vo 
        ON vo.visit_occurrence_id = j.visit_occurrence_id
    LEFT JOIN :cdm_schema.concept c
        ON c.concept_id = vo.visit_concept_id
    -- REMOVED: WHERE vo.visit_concept_id IN (9201,9203)
    -- This was excluding ICU patients (32037, 581379)
)

SELECT * FROM final;
