-- 30_view_sofa_components.sql
-- MGH patched version - joins to vw_vitals_core and vw_neuro with charttime
-- Keeps original logic but fixes column names for your patched views


DROP TABLE IF EXISTS results_site_a.sofa_hourly CASCADE;
DROP VIEW IF EXISTS results_site_a.vw_sofa_components CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_sofa_components AS
SELECT 
  b.person_id, 
  b.hr,
  pf.pf_ratio, 
  l.platelets, 
  l.bilirubin, 
  v.map, 
  n.gcs_total, 
  l.creatinine, 
  u.urine_24h_ml, 
  r.rrt_active
FROM (
  -- generate hourly grid from first to last measurement per patient
  -- (this is what creates the 600M rows - dates are shifted so keep full range)
  SELECT 
    person_id, 
    generate_series(
      MIN(measurement_datetime), 
      MAX(measurement_datetime), 
      '1 hour'
    ) AS hr 
  FROM :cdm_schema.measurement 
  GROUP BY 1
) b

LEFT JOIN :results_schema.view_pao2_fio2_pairs pf 
  ON pf.person_id = b.person_id 
  AND pf.pao2_datetime BETWEEN b.hr - interval '2 hours' AND b.hr

LEFT JOIN :results_schema.view_labs_core l 
  ON l.person_id = b.person_id 
  AND l.measurement_datetime BETWEEN b.hr - interval '24 hours' AND b.hr

-- CHANGED: use vw_vitals_core and charttime (not measurement_datetime)
LEFT JOIN :results_schema.vw_vitals_core v 
  ON v.person_id = b.person_id 
  AND v.charttime BETWEEN b.hr - interval '1 hour' AND b.hr

-- CHANGED: use vw_neuro and charttime, 24h window for GCS
LEFT JOIN :results_schema.vw_neuro n 
  ON n.person_id = b.person_id 
  AND n.charttime BETWEEN b.hr - interval '24 hours' AND b.hr

LEFT JOIN :results_schema.view_urine_24h u 
  ON u.person_id = b.person_id 
  AND u.measurement_datetime BETWEEN b.hr - interval '1 hour' AND b.hr

LEFT JOIN :results_schema.view_rrt r 
  ON r.person_id = b.person_id 
  AND b.hr BETWEEN r.start_datetime AND r.end_datetime;
