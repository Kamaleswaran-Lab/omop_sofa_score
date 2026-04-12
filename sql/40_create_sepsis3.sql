-- OMOP SOFA v4.4 - Sepsis-3 cases
-- FIX #5: Uses pre-infection baseline (not last_available)

DROP TABLE IF EXISTS results.sepsis3_cases CASCADE;

CREATE TABLE results.sepsis3_cases AS
WITH baseline_sofa AS (
    SELECT 
        si.person_id,
        si.infection_onset,
        COALESCE(MIN(sh.total_sofa), 0) AS baseline_sofa
    FROM results.v_suspected_infection si
    LEFT JOIN results.sofa_hourly sh 
        ON sh.person_id = si.person_id
        AND sh.charttime BETWEEN si.infection_onset - INTERVAL '72 hours' 
                             AND si.infection_onset - INTERVAL '24 hours'
    GROUP BY si.person_id, si.infection_onset
)
SELECT
    si.person_id,
    si.infection_onset,
    si.abx_start,
    si.culture_time,
    si.hours_apart,
    b.baseline_sofa,
    sh.charttime AS sepsis_onset,
    sh.total_sofa AS peak_sofa,
    sh.total_sofa - b.baseline_sofa AS delta_sofa,
    si.antibiotic_name,
    si.culture_type
FROM results.v_suspected_infection si
JOIN baseline_sofa b 
    ON b.person_id = si.person_id 
    AND b.infection_onset = si.infection_onset
JOIN LATERAL (
    SELECT charttime, total_sofa
    FROM results.sofa_hourly
    WHERE person_id = si.person_id
      AND charttime BETWEEN si.infection_onset 
                        AND si.infection_onset + INTERVAL '48 hours'
      AND total_sofa - b.baseline_sofa >= 2
    ORDER BY charttime
    LIMIT 1
) sh ON true;

CREATE INDEX idx_sepsis3_person ON results.sepsis3_cases(person_id);
CREATE INDEX idx_sepsis3_onset ON results.sepsis3_cases(sepsis_onset);

SELECT 'Sepsis-3 cases created (FIX #5: pre-infection baseline)' AS status;
