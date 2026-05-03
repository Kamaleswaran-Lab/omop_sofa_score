-- 31_create_sofa_hourly.sql
-- Materialize event-scoped hourly SOFA scores with query planner protections.

DROP TABLE IF EXISTS :results_schema.sofa_hourly CASCADE;

-- 1) Force materialization of the base cohort to prevent Postgres from 
-- evaluating the OMOP tables multiple times in a nested loop death-spiral.
DROP TABLE IF EXISTS :results_schema.tmp_infection_hours CASCADE;
CREATE UNLOGGED TABLE :results_schema.tmp_infection_hours AS
SELECT DISTINCT
  io.person_id,
  gs.hr
FROM :results_schema.view_infection_onset io
CROSS JOIN LATERAL generate_series(
  date_trunc('hour', io.infection_onset - interval '48 hours'),
  date_trunc('hour', io.infection_onset + interval '24 hours'),
  interval '1 hour'
) AS gs(hr);

CREATE INDEX ix_tmp_inf_hr_pid ON :results_schema.tmp_infection_hours(person_id, hr);
ANALYZE :results_schema.tmp_infection_hours;

-- 2) Now safely calculate the components using the materialized boundary
-- We redefine the logic here to bypass the slow view completely.
CREATE UNLOGGED TABLE :results_schema.sofa_hourly AS
WITH raw_components AS (
  SELECT
    b.person_id,
    b.hr,
    MIN(pf.pf_ratio) AS pf_ratio,
    BOOL_OR(vent.person_id IS NOT NULL) AS respiratory_support,
    MIN(l.platelets) AS platelets,
    MAX(l.bilirubin) AS bilirubin,
    MIN(v.map) AS map,
    MAX(vp.nee_factor) AS max_vasopressor_nee_factor,
    MIN(n.gcs_total) AS gcs_total,
    MAX(l.creatinine) AS creatinine,
    MIN(u.urine_24h_ml) AS urine_24h_ml,
    BOOL_OR(COALESCE(r.rrt_active, false)) AS rrt_active
  FROM :results_schema.tmp_infection_hours b
  LEFT JOIN :results_schema.view_pao2_fio2_pairs pf
    ON pf.person_id = b.person_id AND pf.pao2_datetime BETWEEN b.hr - interval '2 hours' AND b.hr
  LEFT JOIN :results_schema.view_ventilation vent
    ON vent.person_id = b.person_id AND b.hr BETWEEN vent.start_datetime AND vent.end_datetime
  LEFT JOIN :results_schema.view_labs_core l
    ON l.person_id = b.person_id AND l.measurement_datetime BETWEEN b.hr - interval '24 hours' AND b.hr
  LEFT JOIN :results_schema.vw_vitals_core v
    ON v.person_id = b.person_id AND v.charttime BETWEEN b.hr - interval '1 hour' AND b.hr
  LEFT JOIN :results_schema.view_vasopressors_nee vp
    ON vp.person_id = b.person_id AND b.hr BETWEEN vp.start_datetime AND vp.end_datetime
  LEFT JOIN :results_schema.vw_neuro n
    ON n.person_id = b.person_id AND n.charttime BETWEEN b.hr - interval '24 hours' AND b.hr
  LEFT JOIN :results_schema.view_urine_24h u
    ON u.person_id = b.person_id AND u.measurement_datetime BETWEEN b.hr - interval '1 hour' AND b.hr
  LEFT JOIN :results_schema.view_rrt r
    ON r.person_id = b.person_id AND b.hr BETWEEN r.start_datetime AND r.end_datetime
  GROUP BY b.person_id, b.hr
),
scored AS (
  SELECT
    *,
    CASE WHEN pf_ratio IS NULL THEN 0 WHEN pf_ratio >= 400 THEN 0 WHEN pf_ratio >= 300 THEN 1 WHEN pf_ratio >= 200 THEN 2 WHEN pf_ratio >= 100 AND respiratory_support THEN 3 WHEN pf_ratio < 100 AND respiratory_support THEN 4 ELSE 2 END AS respiratory_sofa,
    CASE WHEN platelets IS NULL THEN 0 WHEN platelets >= 150 THEN 0 WHEN platelets >= 100 THEN 1 WHEN platelets >= 50 THEN 2 WHEN platelets >= 20 THEN 3 ELSE 4 END AS coagulation_sofa,
    CASE WHEN bilirubin IS NULL THEN 0 WHEN bilirubin < 1.2 THEN 0 WHEN bilirubin <= 1.9 THEN 1 WHEN bilirubin <= 5.9 THEN 2 WHEN bilirubin <= 11.9 THEN 3 ELSE 4 END AS liver_sofa,
    CASE WHEN max_vasopressor_nee_factor IS NOT NULL THEN 3 WHEN map IS NULL THEN 0 WHEN map >= 70 THEN 0 ELSE 1 END AS cardiovascular_sofa,
    CASE WHEN gcs_total IS NULL THEN 0 WHEN gcs_total >= 15 THEN 0 WHEN gcs_total >= 13 THEN 1 WHEN gcs_total >= 10 THEN 2 WHEN gcs_total >= 6 THEN 3 ELSE 4 END AS neurologic_sofa,
    CASE WHEN rrt_active THEN 4 WHEN urine_24h_ml IS NOT NULL AND urine_24h_ml < 200 THEN 4 WHEN urine_24h_ml IS NOT NULL AND urine_24h_ml < 500 THEN 3 WHEN creatinine IS NULL THEN 0 WHEN creatinine < 1.2 THEN 0 WHEN creatinine <= 1.9 THEN 1 WHEN creatinine <= 3.4 THEN 2 WHEN creatinine <= 4.9 THEN 3 ELSE 4 END AS renal_sofa,
    ( (pf_ratio IS NOT NULL)::int + (platelets IS NOT NULL)::int + (bilirubin IS NOT NULL)::int + (map IS NOT NULL OR max_vasopressor_nee_factor IS NOT NULL)::int + (gcs_total IS NOT NULL)::int + (creatinine IS NOT NULL OR urine_24h_ml IS NOT NULL OR rrt_active)::int ) AS components_observed
  FROM raw_components
)
SELECT
  person_id, hr, pf_ratio, respiratory_support, platelets, bilirubin, map, max_vasopressor_nee_factor, gcs_total, creatinine, urine_24h_ml, rrt_active,
  respiratory_sofa, coagulation_sofa, liver_sofa, cardiovascular_sofa, neurologic_sofa, renal_sofa,
  respiratory_sofa + coagulation_sofa + liver_sofa + cardiovascular_sofa + neurologic_sofa + renal_sofa AS total_sofa,
  components_observed
FROM scored;

ALTER TABLE :results_schema.sofa_hourly SET LOGGED;
CREATE INDEX IF NOT EXISTS ix_sofa_hourly_pid_hr ON :results_schema.sofa_hourly(person_id, hr);
CREATE INDEX IF NOT EXISTS ix_sofa_hourly_hr ON :results_schema.sofa_hourly(hr);
ANALYZE :results_schema.sofa_hourly;
DROP TABLE IF EXISTS :results_schema.tmp_infection_hours CASCADE;
