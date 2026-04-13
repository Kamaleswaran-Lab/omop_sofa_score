-- Combine all SOFA components
DROP VIEW IF EXISTS results_site_a.vw_sofa_components CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_sofa_components AS
SELECT 
    COALESCE(l.person_id, v.person_id, p.person_id, n.person_id, u.person_id, r.person_id, vp.person_id) AS person_id,
    COALESCE(l.charttime, v.charttime, p.pao2_time, n.charttime, u.charttime, r.charttime, vp.charttime) AS charttime,
    -- Labs
    l.creatinine,
    l.bilirubin,
    l.platelets,
    l.lactate,
    l.urine_output,
    -- Vitals
    v.temperature,
    v.heart_rate,
    v.sbp,
    v.dbp,
    v.map,
    v.resp_rate,
    v.spo2,
    -- Respiratory
    p.pao2,
    p.fio2,
    p.pf_ratio,
    p.delta_minutes AS fio2_delta_minutes,
    p.spo2 AS spo2_paired,
    -- Ventilation
    vent.ventilated,
    -- Neuro
    n.gcs_total,
    n.rass_score,
    -- Renal
    u.urine_24h,
    r.rrt_active,
    -- Vasopressors
    vp.nee_dose,
    vp.vasopressin_dose,
    vp.dopamine_dose,
    vp.norepi_dose
FROM results_site_a.vw_labs_core l
FULL OUTER JOIN results_site_a.vw_vitals_core v 
    ON l.person_id = v.person_id AND l.charttime = v.charttime
FULL OUTER JOIN results_site_a.vw_pao2_fio2_pairs p 
    ON COALESCE(l.person_id, v.person_id) = p.person_id 
    AND COALESCE(l.charttime, v.charttime) = p.pao2_time
FULL OUTER JOIN results_site_a.vw_ventilation vent
    ON COALESCE(l.person_id, v.person_id, p.person_id) = vent.person_id
    AND COALESCE(l.charttime, v.charttime, p.pao2_time) = vent.charttime
FULL OUTER JOIN results_site_a.vw_neuro n 
    ON COALESCE(l.person_id, v.person_id, p.person_id, vent.person_id) = n.person_id
    AND COALESCE(l.charttime, v.charttime, p.pao2_time, vent.charttime) = n.charttime
FULL OUTER JOIN results_site_a.vw_urine_24h u 
    ON COALESCE(l.person_id, v.person_id, p.person_id, vent.person_id, n.person_id) = u.person_id
    AND COALESCE(l.charttime, v.charttime, p.pao2_time, vent.charttime, n.charttime) = u.charttime
FULL OUTER JOIN results_site_a.vw_rrt r 
    ON COALESCE(l.person_id, v.person_id, p.person_id, vent.person_id, n.person_id, u.person_id) = r.person_id
    AND COALESCE(l.charttime, v.charttime, p.pao2_time, vent.charttime, n.charttime, u.charttime) = r.charttime
FULL OUTER JOIN results_site_a.vw_vasopressors_nee vp 
    ON COALESCE(l.person_id, v.person_id, p.person_id, vent.person_id, n.person_id, u.person_id, r.person_id) = vp.person_id
    AND COALESCE(l.charttime, v.charttime, p.pao2_time, vent.charttime, n.charttime, u.charttime, r.charttime) = vp.charttime;