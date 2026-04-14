
-- 53_cdc_ase_organ_dysfunction.sql
-- CDC ASE organ dysfunction within ±2 days of blood culture
-- FIXED: 'window' is a reserved keyword in PostgreSQL

DROP TABLE IF EXISTS :results_schema.cdc_ase_organ_dysfunction;
CREATE TABLE :results_schema.cdc_ase_organ_dysfunction AS
WITH bc AS (
  SELECT * FROM :results_schema.cdc_ase_blood_cultures
),
win AS (  -- changed from 'window' to 'win'
  SELECT person_id, visit_occurrence_id, culture_date,
    culture_date - 2 AS win_start,
    culture_date + 2 AS win_end
  FROM bc
),
-- 1) Vasopressor initiation
vaso AS (
  SELECT DISTINCT w.person_id, w.visit_occurrence_id, w.culture_date,
    DATE(de.drug_exposure_start_datetime) AS event_date,
    'vasopressor' AS od_type
  FROM win w
  JOIN :cdm_schema.drug_exposure de 
    ON de.person_id = w.person_id AND de.visit_occurrence_id = w.visit_occurrence_id
  WHERE de.drug_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vasopressor_concepts)
    AND DATE(de.drug_exposure_start_datetime) BETWEEN w.win_start AND w.win_end
    AND NOT EXISTS (
      SELECT 1 FROM :cdm_schema.drug_exposure de2
      WHERE de2.person_id = de.person_id
        AND de2.drug_concept_id = de.drug_concept_id
        AND DATE(de2.drug_exposure_start_datetime) = DATE(de.drug_exposure_start_datetime) - 1
    )
),
-- 2) Mechanical ventilation initiation
vent AS (
  SELECT DISTINCT w.person_id, w.visit_occurrence_id, w.culture_date,
    DATE(p.procedure_date) AS event_date,
    'ventilation' AS od_type
  FROM win w
  JOIN :cdm_schema.procedure_occurrence p 
    ON p.person_id = w.person_id AND p.visit_occurrence_id = w.visit_occurrence_id
  WHERE p.procedure_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vent_concepts)
    AND DATE(p.procedure_date) BETWEEN w.win_start AND w.win_end
),
-- 3) Labs for renal, hepatic, platelet, lactate
labs AS (
  SELECT 
    m.person_id, m.visit_occurrence_id,
    DATE(m.measurement_date) AS lab_date,
    m.measurement_concept_id,
    m.value_as_number
  FROM :cdm_schema.measurement m
  WHERE m.value_as_number IS NOT NULL
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
  FROM labs l
),
baseline AS (
  SELECT w.person_id, w.visit_occurrence_id, w.culture_date,
    vo.visit_start_date,
    CASE WHEN w.culture_date - vo.visit_start_date < 2 THEN 'community' ELSE 'hospital' END AS onset_type,
    w.win_start, w.win_end
  FROM win w
  JOIN :cdm_schema.visit_occurrence vo ON vo.visit_occurrence_id = w.visit_occurrence_id
),
renal AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date,
    'renal' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id=b.person_id AND l.visit_occurrence_id=b.visit_occurrence_id
  WHERE l.lab_type IN ('creatinine','egfr')
    AND l.lab_date BETWEEN b.win_start AND b.win_end
    AND NOT EXISTS (SELECT 1 FROM :cdm_schema.condition_occurrence co 
                    WHERE co.person_id=b.person_id 
                    AND co.condition_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_esrd_concepts))
  GROUP BY b.person_id,b.visit_occurrence_id,b.culture_date
  HAVING 
    MAX(CASE WHEN l.lab_type='creatinine' THEN l.value_as_number END) >= 2 * MIN(CASE WHEN l.lab_type='creatinine' THEN l.value_as_number END)
),
hepatic AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 'hepatic' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id=b.person_id AND l.visit_occurrence_id=b.visit_occurrence_id
  WHERE l.lab_type='bilirubin' AND l.lab_date BETWEEN b.win_start AND b.win_end
  GROUP BY b.person_id,b.visit_occurrence_id,b.culture_date
  HAVING MAX(l.value_as_number) >= 2.0 AND MAX(l.value_as_number) >= 2 * MIN(l.value_as_number)
),
platelet AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 'platelet' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id=b.person_id AND l.visit_occurrence_id=b.visit_occurrence_id
  WHERE l.lab_type='platelet' AND l.lab_date BETWEEN b.win_start AND b.win_end
  GROUP BY b.person_id,b.visit_occurrence_id,b.culture_date
  HAVING MIN(l.value_as_number) < 100 AND MIN(l.value_as_number) <= 0.5 * MAX(l.value_as_number) AND MAX(l.value_as_number) >= 100
),
lactate AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(l.lab_date) AS event_date, 'lactate' AS od_type
  FROM baseline b
  JOIN lab_map l ON l.person_id=b.person_id AND l.visit_occurrence_id=b.visit_occurrence_id
  WHERE l.lab_type='lactate' AND l.lab_date BETWEEN b.win_start AND b.win_end AND l.value_as_number >= 2.0
  GROUP BY b.person_id,b.visit_occurrence_id,b.culture_date
)
SELECT * FROM vaso
UNION ALL SELECT * FROM vent
UNION ALL SELECT * FROM renal
UNION ALL SELECT * FROM hepatic
UNION ALL SELECT * FROM platelet
UNION ALL SELECT * FROM lactate;
