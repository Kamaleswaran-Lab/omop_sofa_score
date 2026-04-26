DROP TABLE IF EXISTS :results_schema.sofa_hourly;
CREATE TABLE :results_schema.sofa_hourly AS SELECT * FROM :results_schema.vw_sofa_components;