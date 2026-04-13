
-- RUN_ALL_cdc_ase.sql
-- CDC Adult Sepsis Event implementation for OMOP CDM
-- Integrates with Kamaleswaran-Lab omop_sofa_score repo

\set cdm_schema omopcdm
\set vocab_schema vocabulary
\set results_schema results_site_a

\i sql/50_cdc_ase_parameters.sql
\i sql/51_cdc_ase_blood_cultures.sql
\i sql/52_cdc_ase_qad.sql
\i sql/53_cdc_ase_organ_dysfunction.sql
\i sql/54_cdc_ase_cases.sql

-- Summary
SELECT onset_type, COUNT(*) AS cases, COUNT(DISTINCT person_id) AS patients
FROM :results_schema.cdc_ase_cases
GROUP BY onset_type;

-- Compare to Sepsis-3 if exists
SELECT 'CDC_ASE' AS definition, COUNT(*) FROM :results_schema.cdc_ase_cases
UNION ALL
SELECT 'Sepsis3_enhanced', COUNT(*) FROM :results_schema.sepsis3_enhanced;
