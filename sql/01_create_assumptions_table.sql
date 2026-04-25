-- Assumptions table for site-specific concepts
DROP TABLE IF EXISTS :results_schema.sofa_assumptions;
CREATE TABLE :results_schema.sofa_assumptions (
  parameter text PRIMARY KEY,
  value text
);
INSERT INTO :results_schema.sofa_assumptions VALUES
('vasopressor_units', 'mcg/kg/min'),
('bilirubin_unit', 'mg/dL'),
('creatinine_unit', 'mg/dL');
