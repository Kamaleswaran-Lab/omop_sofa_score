-- 53_cdc_ase_organ_dysfunction.sql
--  CHoRUS FIX: direct drug/procedure IDs + COALESCE datetime, no concept_ancestor
-- Includes full   ventilation mapping across procedures, devices, and measurements

DROP TABLE IF EXISTS :results_schema.ase_organ_dysfunction CASCADE;
CREATE TABLE :results_schema.ase_organ_dysfunction AS
SELECT
  bc.person_id,
  bc.culture_datetime,
  
  -- 1. Vasopressors
  EXISTS (
    SELECT 1 FROM :cdm_schema.drug_exposure de
    JOIN :vocab_schema.concept c ON c.concept_id = de.drug_concept_id
    WHERE de.person_id = bc.person_id
      AND COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp)
          BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
      AND c.domain_id = 'Drug'
      AND (
        c.concept_name ILIKE '%norepinephrine%' OR
        c.concept_name ILIKE '%epinephrine%' OR
        c.concept_name ILIKE '%vasopressin%' OR
        c.concept_name ILIKE '%dopamine%' OR
        c.concept_name ILIKE '%phenylephrine%'
      )
      AND c.concept_name NOT ILIKE '%ophthalmic%'
      AND c.concept_name NOT ILIKE '%nasal%'
      AND c.concept_name NOT ILIKE '%topical%'
      AND c.concept_name NOT ILIKE '%inhalation%'
  ) AS vaso_init,
  
  -- 2. Ventilation (Procedures, Devices, and Measurements)
  EXISTS (
    -- A. Procedures (Intubations)
    SELECT 1 FROM :cdm_schema.procedure_occurrence po
    WHERE po.person_id = bc.person_id
      AND COALESCE(po.procedure_datetime, po.procedure_date::timestamp)
          BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
      AND po.procedure_concept_id IN (4202832, 4058031, 4048158, 4061705, 42736715) 
    
    UNION ALL
    
    -- B. Devices (Ventilators & Oxygen Equipment)
    SELECT 1 FROM :cdm_schema.device_exposure de
    WHERE de.person_id = bc.person_id
      AND COALESCE(de.device_exposure_start_datetime, de.device_exposure_start_date::timestamp)
          BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
      AND de.device_concept_id IN (4049107, 4230167, 45768192, 4222965) -- Added MGH 4222965
      
    UNION ALL
    
    -- C. Measurements (Vent Respirations - 5M rows at MGH)
    SELECT 1 FROM :cdm_schema.measurement m
    WHERE m.person_id = bc.person_id
      AND COALESCE(m.measurement_datetime, m.measurement_date::timestamp)
          BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
      AND m.measurement_concept_id IN (2000000223, 2147483344) 
  ) AS vent_init,
  
  -- 3. Lactate >= 2.0 (Fixed from Bilirubin)
  EXISTS (
    SELECT 1 FROM :cdm_schema.measurement m
    WHERE m.person_id = bc.person_id
      AND m.measurement_concept_id IN (3047181, 3014111, 3022250, 3008037) -- TRUE lactate
      AND m.value_as_number >= 2.0
      AND COALESCE(m.measurement_datetime, m.measurement_date::timestamp)
          BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
  ) AS lactate_high
  
FROM :results_schema.ase_blood_cultures bc;
