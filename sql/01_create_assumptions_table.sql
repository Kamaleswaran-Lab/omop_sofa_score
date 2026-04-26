DROP TABLE IF EXISTS results_site_a.assumptions CASCADE;
CREATE TABLE results_site_a.assumptions (
    domain TEXT,
    concept_id INTEGER,   -- <-- ADD THIS
    parameter TEXT,
    value TEXT,
    description TEXT
);

-- 1. Parameters (your original 6 rows)
INSERT INTO results_site_a.assumptions (domain, parameter, value, description) VALUES
('antibiotic','window_hours','72','Hours between culture and antibiotic for infection onset'),  -- changed to 72 to match your view
('culture','lookback_hours','48','Lookback for cultures'),
('sofa','baseline_window','24','Hours before infection for baseline SOFA'),
('sofa','delta_threshold','2','SOFA increase for Sepsis-3'),
('ase','qad_days','4','Qualified antibiotic days for ASE'),
('ase','organ_window','7','Days for organ dysfunction');

-- 2. Antibiotic concept_ids (what your view joins on)
INSERT INTO results_site_a.assumptions (domain, concept_id)
SELECT DISTINCT 'antibiotic', descendant_concept_id
FROM vocabulary.concept_ancestor
WHERE ancestor_concept_id = 21602796;  -- Antibacterial agent
