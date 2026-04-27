-- 00_assumptions.sql
-- OMOP CDM v5.4 Sepsis Phenotyping - Assumptions and Concept Sets
--  

-- Drop and recreate
DROP TABLE IF EXISTS :results_schema.assumptions CASCADE;
CREATE TABLE :results_schema.assumptions (
    domain TEXT NOT NULL,
    parameter TEXT NOT NULL,
    value TEXT NOT NULL,
    description TEXT,
    PRIMARY KEY (domain, parameter, value)
);

-- Parameters
INSERT INTO :results_schema.assumptions (domain, parameter, value, description) VALUES
('antibiotic','window_hours','72','Hours between culture and antibiotic for infection onset'),
('culture','lookback_hours','48','Lookback window for cultures'),
('sofa','baseline_window','24','Hours before infection for SOFA baseline'),
('sofa','delta_threshold','2','SOFA increase required for Sepsis-3'),
('ase','qad_days','4','Qualified Antibiotic Days for ASE'),
('ase','organ_window','7','Days for organ dysfunction after infection'),
('route','filter_mode','auto','auto=strict if site has routes, else permissive');

-- ANTIBIOTIC CONCEPTS
-- Verified IDs:
-- 21602796 = SNOMED 281786004 | Antibacterial agent (standard, non-hierarchical)
-- This ancestor captures ~2,800 standard RxNorm ingredients and clinical drugs
-- We filter to standard concepts only to avoid 110k non-standard descendants

INSERT INTO :results_schema.assumptions (domain, parameter, value, description)
SELECT DISTINCT
    'antibiotic' AS domain,
    'concept_id' AS parameter,
    ca.descendant_concept_id::text AS value,
    c.concept_name AS description
FROM :vocab_schema.concept_ancestor ca
JOIN :vocab_schema.concept c ON c.concept_id = ca.descendant_concept_id
WHERE ca.ancestor_concept_id = 21602796  -- Antibacterial agent
  AND c.standard_concept = 'S'
  AND c.domain_id = 'Drug'
  AND c.concept_class_id IN ('Ingredient','Clinical Drug','Branded Drug','Quant Clinical Drug','Quant Branded Drug')
  AND c.invalid_reason IS NULL;

-- Verify count (should be ~2,800-3,200 depending on vocabulary version)
-- SELECT COUNT(*) FROM :results_schema.assumptions WHERE domain='antibiotic' AND parameter='concept_id';
