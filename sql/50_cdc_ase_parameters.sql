
-- 50_cdc_ase_parameters.sql
-- CDC Adult Sepsis Event (ASE) parameters for OMOP CDM v5.4+
-- Source: CDC Sepsis Surveillance Toolkit Aug 2018
-- https://www.cdc.gov/sepsis/media/pdfs/Sepsis-Surveillance-Toolkit-Aug-2018-508.pdf

-- Set schemas via psql variables: :cdm_schema, :vocab_schema, :results_schema

-- 1) Blood culture concepts (OMOP)
DROP TABLE IF EXISTS :results_schema.cdc_ase_blood_culture_concepts;
CREATE TABLE :results_schema.cdc_ase_blood_culture_concepts AS
SELECT DISTINCT c.concept_id
FROM :vocab_schema.concept c
WHERE (
  lower(c.concept_name) LIKE '%blood%culture%' 
  OR c.concept_code IN ('600-7','630-4','635-3') -- LOINC examples
)
AND c.domain_id IN ('Procedure','Measurement')
AND c.standard_concept = 'S';

-- 2) Qualifying antimicrobials per Appendix A
DROP TABLE IF EXISTS :results_schema.cdc_ase_antimicrobial_concepts;
CREATE TABLE :results_schema.cdc_ase_antimicrobial_concepts AS
WITH abx_names AS (
  SELECT unnest(ARRAY[
    'amoxicillin','ampicillin','ampicillin-sulbactam','azithromycin','aztreonam',
    'cefaclor','cefadroxil','cefazolin','cefdinir','cefditoren','cefepime',
    'cefotaxime','cefotetan','cefoxitin','cefpodoxime','cefprozil','ceftaroline',
    'ceftazidime','ceftazidime-avibactam','ceftolozane-tazobactam','ceftriaxone',
    'cefuroxime','cephalexin','chloramphenicol','ciprofloxacin','clarithromycin',
    'clindamycin','dalbavancin','daptomycin','dicloxacillin','doxycycline',
    'ertapenem','erythromycin','fidaxomicin','gemifloxacin','gentamicin',
    'imipenem','imipenem-cilastatin','levofloxacin','linezolid','meropenem',
    'metronidazole','moxifloxacin','nafcillin','oritavancin','oxacillin',
    'penicillin','piperacillin','piperacillin-tazobactam','tedizolid',
    'telavancin','tigecycline','tobramycin','trimethoprim','trimethoprim-sulfamethoxazole',
    'vancomycin',
    -- antifungals
    'amphotericin b','anidulafungin','caspofungin','fluconazole','isavuconazonium',
    'itraconazole','micafungin','posaconazole','voriconazole',
    -- antivirals
    'acyclovir','cidofovir','foscarnet','ganciclovir','oseltamivir','peramivir'
  ]) AS drug_name
)
SELECT DISTINCT c.concept_id, lower(c.concept_name) AS drug_name, c.concept_class_id
FROM :vocab_schema.concept c
JOIN abx_names a ON lower(c.concept_name) LIKE a.drug_name || '%'
WHERE c.vocabulary_id IN ('RxNorm','RxNorm Extension')
  AND c.standard_concept = 'S'
  AND c.concept_class_id IN ('Ingredient','Clinical Drug');

-- 3) Vasopressors per Appendix B
DROP TABLE IF EXISTS :results_schema.cdc_ase_vasopressor_concepts;
CREATE TABLE :results_schema.cdc_ase_vasopressor_concepts AS
SELECT DISTINCT c.concept_id
FROM :vocab_schema.concept c
WHERE lower(c.concept_name) IN ('norepinephrine','epinephrine','dopamine','phenylephrine','vasopressin')
  AND c.vocabulary_id IN ('RxNorm','RxNorm Extension')
  AND c.standard_concept = 'S';

-- 4) Mechanical ventilation procedure codes
DROP TABLE IF EXISTS :results_schema.cdc_ase_vent_concepts;
CREATE TABLE :results_schema.cdc_ase_vent_concepts AS
SELECT concept_id FROM :vocab_schema.concept WHERE concept_code IN ('5A1935Z','5A1945Z','5A1955Z') -- ICD10PCS
UNION
SELECT concept_id FROM :vocab_schema.concept WHERE concept_code IN ('94002','94003','94004','94656','94657') AND vocabulary_id='CPT4';

-- 5) ESRD exclusion
DROP TABLE IF EXISTS :results_schema.cdc_ase_esrd_concepts;
CREATE TABLE :results_schema.cdc_ase_esrd_concepts AS
SELECT concept_id FROM :vocab_schema.concept WHERE concept_code = 'N18.6' AND vocabulary_id='ICD10CM';
