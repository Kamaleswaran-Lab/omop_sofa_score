CREATE OR REPLACE VIEW :results_schema.vw_sofa_components AS
SELECT b.person_id, b.hr,
  pf.pf_ratio, l.platelets, l.bilirubin, v.map, n.gcs_total, l.creatinine, u.urine_24h_ml, r.rrt_active
FROM (SELECT person_id, generate_series(MIN(measurement_datetime), MAX(measurement_datetime), '1 hour') AS hr FROM :cdm_schema.measurement GROUP BY 1) b
LEFT JOIN :results_schema.view_pao2_fio2_pairs pf ON pf.person_id=b.person_id AND pf.pao2_datetime BETWEEN b.hr - interval '2h' AND b.hr
LEFT JOIN :results_schema.view_labs_core l ON l.person_id=b.person_id AND l.measurement_datetime BETWEEN b.hr - interval '24h' AND b.hr
LEFT JOIN :results_schema.view_vitals_core v ON v.person_id=b.person_id AND v.measurement_datetime BETWEEN b.hr - interval '1h' AND b.hr
LEFT JOIN :results_schema.view_neuro n ON n.person_id=b.person_id AND n.measurement_datetime BETWEEN b.hr - interval '24h' AND b.hr
LEFT JOIN :results_schema.view_urine_24h u ON u.person_id=b.person_id AND u.measurement_datetime BETWEEN b.hr - interval '1h' AND b.hr
LEFT JOIN :results_schema.view_rrt r ON r.person_id=b.person_id AND b.hr BETWEEN r.start_datetime AND r.end_datetime;
