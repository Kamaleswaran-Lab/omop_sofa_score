-- GENERALIZED: finds PaO2 and FiO2 by name, works at MGH + other sites
-- No hardcoded concept IDs
CREATE OR REPLACE VIEW :results_schema.view_pao2_fio2_pairs AS
WITH pao2_concepts AS (
  SELECT concept_id FROM :vocab_schema.concept
  WHERE domain_id = 'Measurement'
    AND (
      concept_name ILIKE 'oxygen [partial pressure] in arterial blood%'
      OR concept_name ILIKE 'po2 arterial%'
      OR concept_name ILIKE 'partial pressure of oxygen in arterial blood%'
      OR concept_name ILIKE 'oxygen partial pressure arterial%'
    )
),
fio2_concepts AS (
  SELECT concept_id FROM :vocab_schema.concept
  WHERE domain_id IN ('Measurement','Observation')
    AND (
      concept_name ILIKE '%fraction of inspired oxygen%'
      OR concept_name ILIKE '%inspired oxygen concentration%'
      OR concept_name ILIKE 'fio2%'
      OR concept_name ILIKE '%oxygen inhalation%'
    )
),
pao2 AS (
  SELECT person_id, measurement_datetime, value_as_number AS pao2
  FROM :cdm_schema.measurement
  WHERE measurement_concept_id IN (SELECT concept_id FROM pao2_concepts)
    AND value_as_number BETWEEN 20 AND 700
),
fio2_meas AS (
  SELECT person_id, measurement_datetime, value_as_number AS fio2_raw
  FROM :cdm_schema.measurement
  WHERE measurement_concept_id IN (SELECT concept_id FROM fio2_concepts)
),
fio2_obs AS (
  SELECT person_id, observation_datetime AS measurement_datetime, value_as_number AS fio2_raw
  FROM :cdm_schema.observation
  WHERE observation_concept_id IN (SELECT concept_id FROM fio2_concepts)
),
fio2_all AS (
  SELECT * FROM fio2_meas UNION ALL SELECT * FROM fio2_obs
),
fio2_norm AS (
  SELECT person_id, measurement_datetime,
         CASE 
           WHEN fio2_raw BETWEEN 21 AND 100 THEN fio2_raw/100.0
           WHEN fio2_raw BETWEEN 0.21 AND 1.0 THEN fio2_raw
           ELSE NULL
         END AS fio2
  FROM fio2_all
  WHERE fio2_raw IS NOT NULL
)
SELECT 
  p.person_id,
  p.measurement_datetime AS pao2_datetime,
  p.pao2,
  f.measurement_datetime AS fio2_datetime,
  f.fio2,
  p.pao2 / NULLIF(f.fio2,0) AS pf_ratio
FROM pao2 p
JOIN LATERAL (
  SELECT fio2, measurement_datetime
  FROM fio2_norm f
  WHERE f.person_id = p.person_id
    AND ABS(EXTRACT(EPOCH FROM (f.measurement_datetime - p.measurement_datetime))) <= 14400
  ORDER BY ABS(EXTRACT(EPOCH FROM (f.measurement_datetime - p.measurement_datetime)))
  LIMIT 1
) f ON true;
