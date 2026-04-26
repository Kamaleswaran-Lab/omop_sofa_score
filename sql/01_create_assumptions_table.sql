 DROP TABLE IF EXISTS results_site_a.assumptions CASCADE;
CREATE TABLE results_site_a.assumptions (
    domain TEXT,
    parameter TEXT,
    value TEXT,
    description TEXT
);

INSERT INTO results_site_a.assumptions VALUES
('antibiotic','window_hours','48','Hours between culture and antibiotic for infection onset'),
('culture','lookback_hours','48','Lookback for cultures'),
('sofa','baseline_window','24','Hours before infection for baseline SOFA'),
('sofa','delta_threshold','2','SOFA increase for Sepsis-3'),
('ase','qad_days','4','Qualified antibiotic days for ASE'),
('ase','organ_window','7','Days for organ dysfunction');
