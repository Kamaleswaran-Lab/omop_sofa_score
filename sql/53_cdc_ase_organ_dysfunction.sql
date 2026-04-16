DROP TABLE IF EXISTS :results_schema.ase_organ_dysfunction CASCADE;
CREATE TABLE :results_schema.ase_organ_dysfunction AS
SELECT
  bc.person_id,
  bc.culture_datetime,
  
  -- Vasopressors: direct   IDs, exclude ophthalmic/inhaled
  EXISTS (
    SELECT 1 FROM :cdm_schema.drug_exposure de
    JOIN :vocab_schema.concept c ON c.concept_id = de.drug_concept_id
    WHERE de.person_id = bc.person_id
      AND de.drug_exposure_start_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
      AND c.domain_id = 'Drug'
      AND (
        c.concept_id IN (1135766,1343916,1321341,40226838,40226837,46275918,19123434) -- phenylephrine, epi, norepi
        OR lower(c.concept_name) LIKE '%vasopressin%'
        OR lower(c.concept_name) LIKE '%dopamine%'
      )
      AND c.concept_name NOT ILIKE '%ophthalmic%'
      AND c.concept_name NOT ILIKE '%inhalation%'
      AND c.concept_name NOT ILIKE '%nasal%'
  ) AS vaso_init,
  
  -- Ventilation: use real intubation codes only
  EXISTS (
    SELECT 1 FROM :cdm_schema.procedure_occurrence po
    WHERE po.person_id = bc.person_id
      AND po.procedure_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
      AND po.procedure_concept_id IN (4202832, 4058031) -- Intubation, ET intubation emergency
  ) AS vent_init,
  
  -- Lactate (already fixed)
  EXISTS (
    SELECT 1 FROM :cdm_schema.measurement m
    WHERE m.person_id = bc.person_id
      AND m.measurement_concept_id IN (3047181, 3014111, 3022250, 3008037)
      AND m.value_as_number >= 2.0
      AND m.measurement_datetime BETWEEN bc.culture_datetime - INTERVAL '2 days' AND bc.culture_datetime + INTERVAL '2 days'
  ) AS lactate_high
  
FROM :results_schema.ase_blood_cultures bc;
