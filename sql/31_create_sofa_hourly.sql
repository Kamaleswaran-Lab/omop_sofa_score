-- OMOP SOFA v4.4 - Create hourly SOFA table

DROP TABLE IF EXISTS results.sofa_hourly CASCADE;

CREATE TABLE results.sofa_hourly AS
SELECT
    person_id,
    visit_occurrence_id,
    charttime,
    COALESCE(resp_score, 0) AS resp,
    COALESCE(cardio_score, 0) AS cardio,
    COALESCE(neuro_score, 0) AS neuro,
    COALESCE(renal_score, 0) AS renal,
    COALESCE(hepatic_score, 0) AS hepatic,
    COALESCE(coag_score, 0) AS coag,
    COALESCE(resp_score, 0) + COALESCE(cardio_score, 0) + COALESCE(neuro_score, 0) + 
    COALESCE(renal_score, 0) + COALESCE(hepatic_score, 0) + COALESCE(coag_score, 0) AS total_sofa,
    pf_ratio,
    nee_total,
    vasopressin_dose,
    gcs_total,
    rass_score,
    urine_24h_rolling_ml,
    creatinine,
    bilirubin,
    platelets
FROM results.v_sofa_components;

CREATE INDEX idx_sofa_hourly_person_time ON results.sofa_hourly(person_id, charttime);
CREATE INDEX idx_sofa_hourly_visit ON results.sofa_hourly(visit_occurrence_id);

SELECT 'SOFA hourly table created' AS status;
