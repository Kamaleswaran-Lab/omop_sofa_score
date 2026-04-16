-- 01_create_assumptions_table.sql
-- PURPOSE: Centralize site-specific concept IDs
-- ADDITIONS: Pre-populate with common OMOP concepts, but YOU MUST edit for your site

DROP TABLE IF EXISTS omop_sofa.assumptions CASCADE;
CREATE TABLE omop_sofa.assumptions (
  domain text NOT NULL,           -- e.g., 'vasopressor','ventilation','icu','blood_culture'
  concept_id integer NOT NULL,
  nee_factor numeric,             -- only for vasopressors
  description text,
  PRIMARY KEY (domain, concept_id)
);

-- Vasopressors (example RxNorm ingredient concepts; add your local codes)
INSERT INTO omop_sofa.assumptions (domain, concept_id, nee_factor, description) VALUES
('vasopressor', 1322088, 1.0, 'norepinephrine'),
('vasopressor', 1343916, 1.0, 'epinephrine'),
('vasopressor', 1363053, 0.1, 'phenylephrine'), -- example factor
('vasopressor', 1319998, 0.01, 'dopamine'),
('vasopressor', 19034224, 0.4, 'vasopressin'); -- add others as needed

-- Ventilation (procedures + devices)
INSERT INTO omop_sofa.assumptions (domain, concept_id, description) VALUES
('ventilation', 4049107, 'Endotracheal intubation'),
('ventilation', 4230167, 'Invasive mechanical ventilation'),
('ventilation', 45768192, 'Mechanical ventilator - device');

-- ICU locations
INSERT INTO omop_sofa.assumptions (domain, concept_id, description) VALUES
('icu', 32037, 'Intensive Care'),
('icu', 581379, 'ICU'),
('icu', 32147, 'Coronary Care Unit');

-- Blood cultures (specimen or procedure)
INSERT INTO omop_sofa.assumptions (domain, concept_id, description) VALUES
('blood_culture', 4046100, 'Blood culture'),
('blood_culture', 4153316, 'Blood for culture');
