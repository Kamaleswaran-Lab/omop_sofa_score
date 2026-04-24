-- 40_create_sepsis3_enhanced.sql
-- FIXED: Real baseline_sofa from 48h pre-infection, deduplicated per visit

DROP TABLE IF EXISTS results_site_a.sepsis3_enhanced CASCADE;

CREATE TABLE results_site_a.sepsis3_enhanced AS
WITH infection_events AS (
    SELECT DISTINCT ON (person_id, visit_occurrence_id)
        person_id,
        visit_occurrence_id,
        infection_onset,
        infection_type,
        antibiotic_start,
        culture_start
    FROM results_site_a.infection_onset_enhanced
    ORDER BY person_id, visit_occurrence_id, infection_onset
),
sofa_with_baseline AS (
    SELECT 
        i.person_id,
        i.visit_occurrence_id,
        i.infection_onset,
        i.infection_type,
        -- REAL baseline: mean SOFA 6-48h before infection
        COALESCE(
            (SELECT AVG(sh.total_sofa) 
             FROM results_site_a.sofa_hourly sh
             WHERE sh.person_id = i.person_id
               AND sh.visit_occurrence_id = i.visit_occurrence_id
               AND sh.charttime BETWEEN i.infection_onset - interval '48 hours'
                                    AND i.infection_onset - interval '6 hours'),
            0
        ) AS baseline_sofa,
        -- Peak SOFA in 24h after infection
        (SELECT MAX(sh.total_sofa)
         FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id
           AND sh.visit_occurrence_id = i.visit_occurrence_id
           AND sh.charttime BETWEEN i.infection_onset - interval '6 hours'
                                AND i.infection_onset + interval '24 hours')
        AS peak_sofa,
        -- Worst organ scores
        (SELECT MAX(sh.resp_sofa) FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id AND sh.charttime BETWEEN i.infection_onset - interval '6h' AND i.infection_onset + interval '24h') AS resp_max,
        (SELECT MAX(sh.coag_sofa) FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id AND sh.charttime BETWEEN i.infection_onset - interval '6h' AND i.infection_onset + interval '24h') AS coag_max,
        (SELECT MAX(sh.liver_sofa) FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id AND sh.charttime BETWEEN i.infection_onset - interval '6h' AND i.infection_onset + interval '24h') AS liver_max,
        (SELECT MAX(sh.cardio_sofa) FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id AND sh.charttime BETWEEN i.infection_onset - interval '6h' AND i.infection_onset + interval '24h') AS cardio_max,
        (SELECT MAX(sh.cns_sofa) FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id AND sh.charttime BETWEEN i.infection_onset - interval '6h' AND i.infection_onset + interval '24h') AS cns_max,
        (SELECT MAX(sh.renal_sofa) FROM results_site_a.sofa_hourly sh
         WHERE sh.person_id = i.person_id AND sh.charttime BETWEEN i.infection_onset - interval '6h' AND i.infection_onset + interval '24h') AS renal_max
    FROM infection_events i
)
SELECT DISTINCT ON (person_id, visit_occurrence_id)
    person_id,
    visit_occurrence_id,
    infection_onset,
    infection_type,
    baseline_sofa,
    peak_sofa,
    (peak_sofa - baseline_sofa) AS delta_sofa,
    resp_max,
    coag_max,
    liver_max,
    cardio_max,
    cns_max,
    renal_max,
    CASE 
        WHEN (peak_sofa - baseline_sofa) >= 2 AND baseline_sofa > 0 THEN TRUE 
        ELSE FALSE 
    END AS meets_sepsis3
FROM sofa_with_baseline
WHERE peak_sofa IS NOT NULL
ORDER BY person_id, visit_occurrence_id, infection_onset;

-- Indexes
CREATE INDEX idx_sepsis3_enhanced_person ON results_site_a.sepsis3_enhanced(person_id);
CREATE INDEX idx_sepsis3_enhanced_visit ON results_site_a.sepsis3_enhanced(visit_occurrence_id);
CREATE INDEX idx_sepsis3_enhanced_meets ON results_site_a.sepsis3_enhanced(meets_sepsis3) WHERE meets_sepsis3 = TRUE;

ANALYZE results_site_a.sepsis3_enhanced;
