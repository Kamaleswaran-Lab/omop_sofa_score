-- 53_cdc_ase_organ_dysfunction.sql
-- CDC ASE organ dysfunction - OPTIMIZED VERSION
-- Pre-filters to presumed infection patients only

DROP TABLE IF EXISTS :results_schema.cdc_ase_organ_dysfunction;
CREATE TABLE :results_schema.cdc_ase_organ_dysfunction AS
WITH pi AS (
  SELECT DISTINCT 
    person_id, 
    visit_occurrence_id, 
    culture_date,
    (culture_date - INTERVAL '2 days')::date AS win_start,
    (culture_date + INTERVAL '2 days')::date AS win_end
  FROM :results_schema.cdc_ase_presumed_infection
),
-- Pre-filter to only relevant patients to avoid full table scans
pi_keys AS (
  SELECT DISTINCT person_id, visit_occurrence_id FROM pi
),
-- 1) Vasopressors: pre-filter drug_exposure
vaso_candidates AS (
  SELECT de.person_id, de.visit_occurrence_id, 
         DATE(de.drug_exposure_start_datetime) AS drug_date,
         de.drug_concept_id
  FROM :cdm_schema.drug_exposure de
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE de.drug_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vasopressor_concepts)
),
vaso AS (
  SELECT DISTINCT 
    pi.person_id, pi.visit_occurrence_id, pi.culture_date,
    vc.drug_date AS event_date,
    'vasopressor'::text AS od_type
  FROM pi
  JOIN vaso_candidates vc USING (person_id, visit_occurrence_id)
  WHERE vc.drug_date BETWEEN pi.win_start AND pi.win_end
    AND NOT EXISTS (
      SELECT 1 FROM vaso_candidates vc2
      WHERE vc2.person_id = vc.person_id 
        AND vc2.visit_occurrence_id = vc.visit_occurrence_id
        AND vc2.drug_concept_id = vc.drug_concept_id
        AND vc2.drug_date = vc.drug_date - 1
    )
),
-- 2) Ventilation: pre-filter procedures
vent_candidates AS (
  SELECT p.person_id, p.visit_occurrence_id, DATE(p.procedure_date) AS proc_date
  FROM :cdm_schema.procedure_occurrence p
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE p.procedure_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vent_concepts)
),
vent AS (
  SELECT DISTINCT pi.person_id, pi.visit_occurrence_id, pi.culture_date,
    vc.proc_date AS event_date, 'ventilation'::text AS od_type
  FROM pi
  JOIN vent_candidates vc USING (person_id, visit_occurrence_id)
  WHERE vc.proc_date BETWEEN pi.win_start AND pi.win_end
),
-- 3) Labs: pre-filter measurements
lab_candidates AS (
  SELECT m.person_id, m.visit_occurrence_id,
    DATE(m.measurement_date) AS lab_date,
    m.measurement_concept_id,
    m.value_as_number,
    CASE 
      WHEN m.measurement_concept_id IN (3022061,3016723,3004327,3013682) THEN 'creatinine'
      WHEN m.measurement_concept_id IN (3022192,3016290,44785819) THEN 'egfr'
      WHEN m.measurement_concept_id IN (3024561,3001927,3013721) THEN 'bilirubin'
      WHEN m.measurement_concept_id IN (3013240,3007461,3013650) THEN 'platelet'
      WHEN m.measurement_concept_id IN (3024731,3005456,3022250) THEN 'lactate'
    END AS lab_type
  FROM :cdm_schema.measurement m
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE m.measurement_concept_id IN (
    3022061,3016723,3004327,3013682,
    3022192,3016290,44785819,
    3024561,3001927,3013721,
    3013240,3007461,3013650,
    3024731,3005456,3022250
  )
  AND m.value_as_number IS NOT NULL
),
-- Get baseline window for each patient
baseline AS (
  SELECT pi.person_id, pi.visit_occurrence_id, pi.culture_date,
    pi.win_start, pi.win_end, vo.visit_start_date
  FROM pi
  JOIN :cdm_schema.visit_occurrence vo USING (visit_occurrence_id)
),
-- Renal dysfunction
renal AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(lc.lab_date) AS event_date, 'renal'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type IN ('creatinine','egfr')
    AND lc.lab_date BETWEEN b.win_start AND b.win_end
    AND NOT EXISTS (
      SELECT 1 FROM :cdm_schema.condition_occurrence co
      WHERE co.person_id = b.person_id
        AND co.condition_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_esrd_concepts)
    )
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MAX(CASE WHEN lc.lab_type='creatinine' THEN lc.value_as_number END) >= 2 * 
         MIN(CASE WHEN lc.lab_type='creatinine' THEN lc.value_as_number END)
),
-- Hepatic dysfunction
hepatic AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(lc.lab_date) AS event_date, 'hepatic'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type = 'bilirubin'
    AND lc.lab_date BETWEEN b.win_start AND b.win_end
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MAX(lc.value_as_number) >= 2.0 
    AND MAX(lc.value_as_number) >= 2 * MIN(lc.value_as_number)
),
-- Platelet dysfunction
platelet AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(lc.lab_date) AS event_date, 'platelet'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type = 'platelet'
    AND lc.lab_date BETWEEN b.win_start AND b.win_end
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MIN(lc.value_as_number) < 100 
    AND MIN(lc.value_as_number) <= 0.5 * MAX(lc.value_as_number)
    AND MAX(lc.value_as_number) >= 100
),
-- Lactate
lactate AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(lc.lab_date) AS event_date, 'lactate'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type = 'lactate'
    AND lc.lab_date BETWEEN b.win_start AND b.win_end
    AND lc.value_as_number >= 2.0
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
)
SELECT * FROM vaso
UNION ALL SELECT * FROM vent
UNION ALL SELECT * FROM renal
UNION ALL SELECT * FROM hepatic
UNION ALL SELECT * FROM platelet
UNION ALL SELECT * FROM lactate;
