CREATE OR REPLACE VIEW results_site_a.vw_sofa_components AS
SELECT 
    COALESCE(l.person_id, v.person_id, n.person_id) AS person_id,
    COALESCE(l.charttime, v.charttime, n.charttime) AS charttime,
    l.creatinine, l.bilirubin, l.platelets, l.lactate,
    p.pao2, p.fio2, p.pf_ratio,
    vn.ventilated,
    n.gcs_total, n.rass_score,
    u.urine_24h, r.rrt_active,
    vp.nee_dose, vp.vasopressin_dose
FROM results_site_a.vw_labs_core l
FULL OUTER JOIN results_site_a.vw_pao2_fio2_pairs p ON l.person_id = p.person_id AND l.charttime = p.pao2_time
FULL OUTER JOIN results_site_a.vw_ventilation vn ON COALESCE(l.person_id, p.person_id) = vn.person_id
FULL OUTER JOIN results_site_a.vw_neuro n ON COALESCE(l.person_id, p.person_id, vn.person_id) = n.person_id
FULL OUTER JOIN results_site_a.vw_urine_24h u ON COALESCE(l.person_id, p.person_id, vn.person_id, n.person_id) = u.person_id
FULL OUTER JOIN results_site_a.vw_rrt r ON COALESCE(l.person_id, p.person_id, vn.person_id, n.person_id, u.person_id) = r.person_id
FULL OUTER JOIN results_site_a.vw_vasopressors_nee vp ON COALESCE(l.person_id, p.person_id, vn.person_id, n.person_id, u.person_id, r.person_id) = vp.person_id;