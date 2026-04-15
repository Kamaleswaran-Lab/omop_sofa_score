-- 53_cdc_ase_organ_dysfunction.sql
-- CDC ASE organ dysfunction - CORRECTED with proper baselines
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
pi_keys AS (SELECT DISTINCT person_id, visit_occurrence_id FROM pi),
baseline AS (
  SELECT pi.person_id, pi.visit_occurrence_id, pi.culture_date, pi.win_start, pi.win_end, 
         vo.visit_start_date, (vo.visit_start_date - INTERVAL '30 days')::date AS lookback_start
  FROM pi JOIN :cdm_schema.visit_occurrence vo USING (visit_occurrence_id)
),
-- 1) Vasopressors: check BOTH drug_exposure and procedure_occurrence
vaso_drug AS (
  SELECT de.person_id, de.visit_occurrence_id, DATE(de.drug_exposure_start_datetime) AS drug_date, de.drug_concept_id
  FROM :cdm_schema.drug_exposure de
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE de.drug_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vasopressor_concepts)
),
vaso_proc AS (
  SELECT p.person_id, p.visit_occurrence_id, DATE(p.procedure_date) AS proc_date, p.procedure_concept_id
  FROM :cdm_schema.procedure_occurrence p
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE p.procedure_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vasopressor_concepts)
),
vaso_all AS (
  SELECT person_id, visit_occurrence_id, drug_date AS event_date, drug_concept_id AS concept_id FROM vaso_drug
  UNION ALL
  SELECT person_id, visit_occurrence_id, proc_date, procedure_concept_id FROM vaso_proc
),
vaso AS (
  SELECT DISTINCT pi.person_id, pi.visit_occurrence_id, pi.culture_date,
    va.event_date, 'vasopressor'::text AS od_type
  FROM pi JOIN vaso_all va USING (person_id, visit_occurrence_id)
  WHERE va.event_date BETWEEN pi.win_start AND pi.win_end
    AND NOT EXISTS (
      SELECT 1 FROM vaso_all va2
      WHERE va2.person_id = va.person_id AND va2.visit_occurrence_id = va.visit_occurrence_id
        AND va2.concept_id = va.concept_id AND va2.event_date = va.event_date - 1
    )
),
-- 2) Ventilation
vent_candidates AS (
  SELECT p.person_id, p.visit_occurrence_id, DATE(p.procedure_date) AS proc_date
  FROM :cdm_schema.procedure_occurrence p
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE p.procedure_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_vent_concepts)
),
vent AS (
  SELECT DISTINCT pi.person_id, pi.visit_occurrence_id, pi.culture_date,
    vc.proc_date AS event_date, 'ventilation'::text AS od_type
  FROM pi JOIN vent_candidates vc USING (person_id, visit_occurrence_id)
  WHERE vc.proc_date BETWEEN pi.win_start AND pi.win_end
),
-- 3) Labs: pre-filter and include baseline period
lab_candidates AS (
  SELECT m.person_id, m.visit_occurrence_id, DATE(m.measurement_date) AS lab_date,
    m.measurement_concept_id, m.value_as_number,
    CASE WHEN m.measurement_concept_id IN (3022061,3016723,3004327,3013682) THEN 'creatinine'
         WHEN m.measurement_concept_id IN (3022192,3016290,44785819) THEN 'egfr'
         WHEN m.measurement_concept_id IN (3024561,3001927,3013721) THEN 'bilirubin'
         WHEN m.measurement_concept_id IN (3013240,3007461,3013650) THEN 'platelet'
         WHEN m.measurement_concept_id IN (3024731,3005456,3022250) THEN 'lactate' END AS lab_type
  FROM :cdm_schema.measurement m
  INNER JOIN pi_keys pk USING (person_id, visit_occurrence_id)
  WHERE m.measurement_concept_id IN (3022061,3016723,3004327,3013682,3022192,3016290,44785819,3024561,3001927,3013721,3013240,3007461,3013650,3024731,3005456,3022250)
    AND m.value_as_number IS NOT NULL
),
-- Renal: compare window max to baseline min (pre-window)
renal AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.lab_date END) AS event_date,
    'renal'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type IN ('creatinine','egfr')
    AND lc.lab_date BETWEEN b.lookback_start AND b.win_end
    AND NOT EXISTS (SELECT 1 FROM :cdm_schema.condition_occurrence co WHERE co.person_id = b.person_id AND co.condition_concept_id IN (SELECT concept_id FROM :results_schema.cdc_ase_esrd_concepts))
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MAX(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end AND lc.lab_type='creatinine' THEN lc.value_as_number END) >= 2.0 *
         COALESCE(MIN(CASE WHEN lc.lab_date < b.win_start AND lc.lab_type='creatinine' THEN lc.value_as_number END), 1.0)
),
-- Hepatic: compare window max to baseline min
hepatic AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.lab_date END) AS event_date,
    'hepatic'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type = 'bilirubin'
    AND lc.lab_date BETWEEN b.lookback_start AND b.win_end
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MAX(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.value_as_number END) >= 2.0
     AND MAX(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.value_as_number END) >= 2.0 *
         COALESCE(MIN(CASE WHEN lc.lab_date < b.win_start THEN lc.value_as_number END), 0.5)
),
-- Platelet: need baseline >=100, then drop to <100 and <=50% of baseline
platelet AS (
  SELECT DISTINCT b.person_id, b.visit_occurrence_id, b.culture_date,
    MIN(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.lab_date END) AS event_date,
    'platelet'::text AS od_type
  FROM baseline b
  JOIN lab_candidates lc USING (person_id, visit_occurrence_id)
  WHERE lc.lab_type = 'platelet'
    AND lc.lab_date BETWEEN b.lookback_start AND b.win_end
  GROUP BY b.person_id, b.visit_occurrence_id, b.culture_date
  HAVING MIN(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.value_as_number END) < 100
     AND MIN(CASE WHEN lc.lab_date BETWEEN b.win_start AND b.win_end THEN lc.value_as_number END) <= 0.5 *
         MAX(CASE WHEN lc.lab_date < b.win_start THEN lc.value_as_number END)
     AND MAX(CASE WHEN lc.lab_date < b.win_start THEN lc.value_as_number END) >= 100
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
SELECT * FROM vaso UNION ALL SELECT * FROM vent UNION ALL SELECT * FROM renal UNION ALL SELECT * FROM hepatic UNION ALL SELECT * FROM platelet UNION ALL SELECT * FROM lactate;
