-- 31_create_sofa_hourly.sql
-- MGH patched: UNLOGGED build, then index, no date filter (dates are shifted)

DROP TABLE IF EXISTS :results_schema.sofa_hourly CASCADE;

-- Build unlogged first for speed (avoid WAL during 600M row insert)
CREATE UNLOGGED TABLE :results_schema.sofa_hourly AS
SELECT
  person_id,
  hr,
  pf_ratio,
  platelets,
  bilirubin,
  map,           -- now populated via vw_vitals_core (concepts 4108290, 3027597)
  gcs_total,     -- now populated via vw_neuro (concept 4093836)
  creatinine,
  urine_24h_ml,
  rrt_active
FROM :results_schema.vw_sofa_components;

-- Make durable
ALTER TABLE :results_schema.sofa_hourly SET LOGGED;

-- Critical indexes for Sepsis-3 joins
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_sofa_hourly_pid_hr 
  ON :results_schema.sofa_hourly(person_id, hr);

CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_sofa_hourly_hr 
  ON :results_schema.sofa_hourly(hr);

-- Stats for planner
ANALYZE :results_schema.sofa_hourly;
