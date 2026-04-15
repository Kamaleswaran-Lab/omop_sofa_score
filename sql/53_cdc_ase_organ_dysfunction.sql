-- 53_cdc_ase_organ_dysfunction.sql
-- CDC ASE organ dysfunction within ±2 days of blood culture
-- Optimized: filters to presumed infections only, avoids full table scans
-- Fixed: 'window' reserved keyword -> 'win'

DROP TABLE IF EXISTS :results_schema.cdc_ase_organ_dysfunction;
CREATE TABLE :results_schema.cdc_ase_organ_dysfunction AS
WITH pi AS (
  SELECT DISTINCT 
    person_id, 
    visit_occurrence_id, 
    culture_date,
    culture_date - INTERVAL '2 days' AS win_start,
    culture_date + INTERVAL '2 days' AS win_end
  FROM :results_schema.cdc_ase_presumed_infection
),
-- 1) Vasopressor initiation (new start)
vaso AS (
  SELECT DISTINCT 
    pi.person_id, 
    pi.visit_occurrence_id, 
    pi.culture_date,
    DATE(de.drug_exposure_start_datetime) AS event_date,
    'vasopressor' AS od_type
  FROM pi
  JOIN :cdm_schema.drug_exposure de 
    ON de.person_id = pi.person_id 
    AND de.visit_occurrence_id = pi.visit_occurrence_id
    AND de.drug_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vasopressor_concepts)
    AND DATE(de.drug_exposure_start_datetime) BETWEEN pi.win_start AND pi.win_end
  WHERE NOT EXISTS (
    SELECT 1 FROM :cdm_schema.drug_exposure de2
    WHERE de2.person_id = de.person_id
      AND de2.drug_concept_id = de.drug_concept_id
      AND de2.visit_occurrence_id = de.visit_occurrence_id
      AND DATE(de2.drug_exposure_start_datetime) = DATE(de.drug_exposure_start_datetime) - INTERVAL '1 day'
  )
),
-- 2) Mechanical ventilation initiation
vent AS (
  SELECT DISTINCT 
    pi.person_id, 
    pi.visit_occurrence_id, 
    pi.culture_date,
    DATE(p.procedure_date) AS event_date,
    'ventilation' AS od_type
  FROM pi
  JOIN :cdm_schema.procedure_occurrence p 
    ON p.person_id = pi.person_id 
    AND p.visit_occurrence_id = pi.visit_occurrence_id
    AND p.procedure_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vent_concepts)
    AND DATE(p.procedure_date) BETWEEN pi.win_start AND pi.win_end
),
-- 3) Labs - pre-filter to relevant patients only
labs_filtered AS (
  SELECT 
    m.person_id, 
    m.visit_occurrence_id,
    DATE(m.measurement_date) AS lab_date,
    m.measurement_concept_id,
    m.value_as_number
  FROM :cdm_schema.measurement m
  JOIN pi ON pi.person_id = m.person_id AND pi.visit_occurrence_id = m.visit_occurrence_id
  WHERE m.measurement_concept_id IN (
    3022061,3016723,3004327,3013682,  -- creatinine
    3022192,3016290,44785819,         -- eGFR
    3024561,3001927,3013721,          -- bilirubin
    3013240,3007461,3013650,          -- platelet
    3024731,3005456,3022250           -- lactate
  )
  AND m.value_as_number IS NOT NULL
  AND DATE(m.measurement_date) BETWEEN (SELECT MIN(win_start) FROM pi) AND (SELECT MAX(win_end) FROM pi)
),
lab_map AS (
  SELECT 
    l.*,
    CASE 
      WHEN measurement_concept_id IN (3022061,3016723,3004327,3013682) THEN 'creatinine'
      WHEN measurement_concept_id IN (3022192,3016290,44785819) THEN 'egfr'
      WHEN measurement_concept_id IN (3024561,3001927,3013721) THEN 'bilirubin'
      WHEN measurement_concept_id IN (3013240,3007461,3013650) THEN 'platelet'
      WHEN measurement_concept_id IN (3024731,3005456,3022250) THEN 'lactate'
    END AS lab_type
  FROM labs_filtered l
),
baseline AS (
  SELECT 
    pi.person_id, 
    pi.visit_occurrence_id, 
    pi.culture_date,
    vo.visit_start_date,
    pi.win_start, 
    pi.win_end
  FROM pi
  JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id = pi.visit_occurrence_id
),
-- Renal: creatinine doubling
renal AS (
  SELECT DISTINCT 
    b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 
    'renal' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id = b.person_id AND l.visit_occurrence_id = b.visit_occurrence_id
  WHERE l.lab_type IN ('creatinine','egfr') 
    AND l.lab_date BETWEEN b.win_start AND b.win_end
    AND NOT EXISTS (
      SELECT 1 FROM :cdm_schema.condition_occurrence co 
      WHERE co.person_id = b.person_id 
        AND co.condition_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_esrd_concepts)
    )
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MAX(CASE WHEN l.lab_type='creatinine' THEN l.value_as_number END) >= 2 * MIN(CASE WHEN l.lab_type='creatinine' THEN l.value_as_number END)
),
-- Hepatic: bilirubin ≥2 and doubling
hepatic AS (
  SELECT DISTINCT 
    b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 
    'hepatic' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id = b.person_id AND l.visit_occurrence_id = b.visit_occurrence_id
  WHERE l.lab_type = 'bilirubin' 
    AND l.lab_date BETWEEN b.win_start AND b.win_end
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MAX(l.value_as_number) >= 2.0 
    AND MAX(l.value_as_number) >= 2 * MIN(l.value_as_number)
),
-- Platelet: <100 and 50% drop from baseline ≥100
platelet AS (
  SELECT DISTINCT 
    b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 
    'platelet' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id = b.person_id AND l.visit_occurrence_id = b.visit_occurrence_id
  WHERE l.lab_type = 'platelet' 
    AND l.lab_date BETWEEN b.win_start AND b.win_end
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MIN(l.value_as_number) < 100 
    AND MIN(l.value_as_number) <= 0.5 * MAX(l.value_as_number) 
    AND MAX(l.value_as_number) >= 100
),
-- Lactate: ≥2.0 mmol/L
lactate AS (
  SELECT DISTINCT 
    b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 
    'lactate' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id = b.person_id AND l.visit_occurrence_id = b.visit_occurrence_id
  WHERE l.lab_type = 'lactate' 
    AND l.lab_date BETWEEN b.win_start AND b.win_end 
    AND l.value_as_number >= 2.0
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
)
SELECT * FROM vaso
UNION ALL SELECT * FROM vent
UNION ALL SELECT * FROM renal
UNION ALL SELECT * FROM hepatic
UNION ALL SELECT * FROM platelet
UNION ALL SELECT * FROM lactate;
