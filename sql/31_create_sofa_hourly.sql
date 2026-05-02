-- 31_create_sofa_hourly.sql
-- Materialize event-scoped hourly SOFA scores.

DROP TABLE IF EXISTS :results_schema.sofa_hourly CASCADE;

-- Build unlogged first for speed and then make durable.
CREATE UNLOGGED TABLE :results_schema.sofa_hourly AS
SELECT
  person_id,
  hr,
  pf_ratio,
  respiratory_support,
  platelets,
  bilirubin,
  map,
  max_vasopressor_nee_factor,
  gcs_total,
  creatinine,
  urine_24h_ml,
  rrt_active,
  respiratory_sofa,
  coagulation_sofa,
  liver_sofa,
  cardiovascular_sofa,
  neurologic_sofa,
  renal_sofa,
  total_sofa,
  components_observed
FROM :results_schema.vw_sofa_components;

-- Make durable
ALTER TABLE :results_schema.sofa_hourly SET LOGGED;

-- Critical indexes for Sepsis-3 joins. Do not use CONCURRENTLY in this runner:
-- many deployments execute the pipeline in one psql transaction.
CREATE INDEX IF NOT EXISTS ix_sofa_hourly_pid_hr
  ON :results_schema.sofa_hourly(person_id, hr);

CREATE INDEX IF NOT EXISTS ix_sofa_hourly_hr
  ON :results_schema.sofa_hourly(hr);

-- Stats for planner
ANALYZE :results_schema.sofa_hourly;
