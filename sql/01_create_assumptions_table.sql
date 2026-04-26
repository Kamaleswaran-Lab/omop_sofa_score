DROP TABLE IF EXISTS :results_schema.sofa_assumptions;
CREATE TABLE :results_schema.sofa_assumptions (parameter text PRIMARY KEY, value text);
INSERT INTO :results_schema.sofa_assumptions VALUES ('version','4.5-fixed');