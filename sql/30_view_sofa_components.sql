-- SOFA components - aligned with fixed views
DROP VIEW IF EXISTS :results_schema.vw_sofa_components CASCADE;

CREATE OR REPLACE VIEW :results_schema.vw_sofa_components AS
WITH hours AS (
  SELECT generate_series(
    (SELECT MIN(charttime)::date FROM :results_schema.vw_labs_core),
    (SELECT MAX(charttime)::date FROM :results_schema.vw_labs_core),
    interval '1 hour'
  ) AS hr
),
patients AS (SELECT DISTINCT person_id FROM :results_schema.vw_labs_core),
grid AS (SELECT p.person_id, h.hr AS charttime FROM patients p CROSS JOIN hours h)
SELECT g.person_id, g.charttime,
  -- labs (last value carried forward 4h)
  (SELECT creatinine FROM :results_schema.vw_labs_core l WHERE l.person_id=g.person_id AND l.charttime <= g.charttime ORDER BY l.charttime DESC LIMIT 1) AS creatinine,
  (SELECT bilirubin FROM :results_schema.vw_labs_core l WHERE l.person_id=g.person_id AND l.charttime <= g.charttime ORDER BY l.charttime DESC LIMIT 1) AS bilirubin,
  (SELECT platelets FROM :results_schema.vw_labs_core l WHERE l.person_id=g.person_id AND l.charttime <= g.charttime ORDER BY l.charttime DESC LIMIT 1) AS platelets,
  -- vitals
  (SELECT map FROM :results_schema.vw_vitals_core v WHERE v.person_id=g.person_id AND v.charttime <= g.charttime ORDER BY v.charttime DESC LIMIT 1) AS map,
  -- pf ratio
  (SELECT pf_ratio FROM :results_schema.vw_pao2_fio2_pairs p WHERE p.person_id=g.person_id AND p.pao2_time <= g.charttime ORDER BY p.pao2_time DESC LIMIT 1) AS pf_ratio,
  -- ventilation
  EXISTS(SELECT 1 FROM :results_schema.ventilation ve WHERE ve.person_id=g.person_id AND g.charttime BETWEEN ve.start_datetime AND ve.end_datetime) AS ventilation_status,
  -- vasopressor
  EXISTS(SELECT 1 FROM :results_schema.vasopressors_nee va WHERE va.person_id=g.person_id AND g.charttime BETWEEN va.start_datetime AND va.end_datetime) AS on_vasopressor,
  (SELECT MAX(nee_factor) FROM :results_schema.vasopressors_nee va WHERE va.person_id=g.person_id AND g.charttime BETWEEN va.start_datetime AND va.end_datetime) AS nee_dose,
  -- neuro
  (SELECT gcs_total FROM :results_schema.vw_neuro n WHERE n.person_id=g.person_id AND n.charttime <= g.charttime ORDER BY n.charttime DESC LIMIT 1) AS gcs,
  -- renal
  (SELECT urine_24h FROM :results_schema.vw_urine_24h u WHERE u.person_id=g.person_id AND u.charttime <= g.charttime ORDER BY u.charttime DESC LIMIT 1) AS urine_24h,
  EXISTS(SELECT 1 FROM :results_schema.vw_rrt r WHERE r.person_id=g.person_id AND g.charttime BETWEEN r.start_datetime AND r.end_datetime) AS rrt_status
FROM grid g;
