-- Materialize hourly SOFA
DROP TABLE IF EXISTS :results_schema.sofa_hourly;
CREATE TABLE :results_schema.sofa_hourly AS
SELECT
  person_id,
  hr AS sofa_datetime,
  (resp+coag+liver+cardio+neuro+renal) AS sofa_total,
  resp, coag, liver, cardio, neuro, renal
FROM :results_schema.view_sofa_components;
CREATE INDEX ON :results_schema.sofa_hourly(person_id, sofa_datetime);
