-- Calculate each SOFA component hourly
CREATE OR REPLACE VIEW :results_schema.view_sofa_components AS
WITH base AS (
  SELECT DISTINCT person_id, generate_series(min_time, max_time, '1 hour') AS hr
  FROM (SELECT person_id, MIN(measurement_datetime) min_time, MAX(measurement_datetime) max_time FROM :results_schema.view_labs_core GROUP BY 1) t
)
SELECT
  b.person_id, b.hr,
  -- respiratory
  CASE WHEN pf.pf_ratio <100 THEN 4 WHEN pf.pf_ratio <200 THEN 3 WHEN pf.pf_ratio <300 THEN 2 WHEN pf.pf_ratio <400 THEN 1 ELSE 0 END AS resp,
  -- coag
  CASE WHEN l_plate.value_corrected <20 THEN 4 WHEN l_plate.value_corrected <50 THEN 3 WHEN l_plate.value_corrected <100 THEN 2 WHEN l_plate.value_corrected <150 THEN 1 ELSE 0 END AS coag,
  -- liver
  CASE WHEN l_bili.value_corrected >12 THEN 4 WHEN l_bili.value_corrected >6 THEN 3 WHEN l_bili.value_corrected >2 THEN 2 WHEN l_bili.value_corrected >1.2 THEN 1 ELSE 0 END AS liver,
  -- cardio
  CASE WHEN v.nee_mcg_kg_min >0.1 THEN 4 WHEN v.nee_mcg_kg_min >0 THEN 3 ELSE 0 END AS cardio,
  -- neuro
  CASE WHEN (n.gcs_eye+n.gcs_verbal+n.gcs_motor) <6 THEN 4 WHEN (n.gcs_eye+n.gcs_verbal+n.gcs_motor) <10 THEN 3 WHEN (n.gcs_eye+n.gcs_verbal+n.gcs_motor) <13 THEN 2 WHEN (n.gcs_eye+n.gcs_verbal+n.gcs_motor) <15 THEN 1 ELSE 0 END AS neuro,
  -- renal
  CASE WHEN r.rt_time IS NOT NULL OR l_creat.value_corrected >5 THEN 4 WHEN l_creat.value_corrected >3.5 THEN 3 WHEN l_creat.value_corrected >2 THEN 2 WHEN l_creat.value_corrected >1.2 THEN 1 ELSE 0 END AS renal
FROM base b
LEFT JOIN :results_schema.view_pao2_fio2_pairs pf ON pf.person_id=b.person_id AND pf.pao2_time BETWEEN b.hr - interval '2h' AND b.hr
LEFT JOIN :results_schema.view_labs_core l_plate ON l_plate.person_id=b.person_id AND l_plate.lab_code='platelets' AND l_plate.measurement_datetime BETWEEN b.hr - interval '24h' AND b.hr
LEFT JOIN :results_schema.view_labs_core l_bili ON l_bili.person_id=b.person_id AND l_bili.lab_code='bili' AND l_bili.measurement_datetime BETWEEN b.hr - interval '24h' AND b.hr
LEFT JOIN :results_schema.view_labs_core l_creat ON l_creat.person_id=b.person_id AND l_creat.lab_code='creat' AND l_creat.measurement_datetime BETWEEN b.hr - interval '24h' AND b.hr
LEFT JOIN :results_schema.view_vasopressors_nee v ON v.person_id=b.person_id AND b.hr BETWEEN v.drug_exposure_start_datetime AND COALESCE(v.drug_exposure_end_datetime, v.drug_exposure_start_datetime + interval '1h')
LEFT JOIN :results_schema.view_neuro n ON n.person_id=b.person_id AND n.measurement_datetime BETWEEN b.hr - interval '24h' AND b.hr
LEFT JOIN :results_schema.view_rrt r ON r.person_id=b.person_id AND r.rrt_time BETWEEN b.hr - interval '24h' AND b.hr;
