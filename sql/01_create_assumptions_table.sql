-- 01_create_assumptions_table.sql
-- Central table for site-specific concept IDs
-- Uses psql variables :results_schema

DROP TABLE IF EXISTS :results_schema.assumptions CASCADE;
CREATE TABLE :results_schema.assumptions (
  domain text NOT NULL,
  concept_id integer NOT NULL,
  nee_factor numeric,
  description text,
  PRIMARY KEY (domain, concept_id)
);

-- Vasopressors: edit/add your local drug_concept_ids
INSERT INTO :results_schema.assumptions (domain, concept_id, nee_factor, description) VALUES
('vasopressor', 1322088, 1.0, 'norepinephrine'),
('vasopressor', 1343916, 1.0, 'epinephrine'),
('vasopressor', 1363053, 0.1, 'phenylephrine'),
('vasopressor', 1319998, 0.01, 'dopamine'),
('vasopressor', 19034224, 0.4, 'vasopressin');

-- Ventilation concepts (procedures + devices)
INSERT INTO :results_schema.assumptions (domain, concept_id, description) VALUES
('ventilation', 4049107, 'Endotracheal intubation'),
('ventilation', 4230167, 'Invasive mechanical ventilation'),
('ventilation', 45768192, 'Mechanical ventilator device');

-- ICU locations
INSERT INTO :results_schema.assumptions (domain, concept_id, description) VALUES
('icu', 32037, 'Intensive Care'),
('icu', 581379, 'ICU'),
('icu', 32147, 'CCU');

-- Blood cultures
INSERT INTO :results_schema.assumptions (domain, concept_id, description) VALUES
('blood_culture', 4046100, 'Blood culture'),
('blood_culture', 4153316, 'Blood for culture');

-- Antibiotics: add your local antibiotic concept_ids here
-- INSERT INTO :results_schema.assumptions (domain, concept_id, description) VALUES ('antibiotic', 1746940, 'example');
