-- MGH CHoRUS Concept Discovery
-- Run these in psql to find actual concept IDs

-- 1. FiO2
SELECT measurement_concept_id, measurement_source_value, 
       COUNT(*) as n, MIN(value_as_number), MAX(value_as_number)
FROM omopcdm.measurement
WHERE LOWER(measurement_source_value) LIKE '%fio2%'
   OR LOWER(measurement_source_value) LIKE '%inspired o2%'
   OR LOWER(measurement_source_value) LIKE '%o2%frac%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

-- 2. PaO2 (you have 4,680 - find more)
SELECT measurement_concept_id, measurement_source_value, COUNT(*) as n
FROM omopcdm.measurement
WHERE LOWER(measurement_source_value) LIKE '%pao2%'
   OR LOWER(measurement_source_value) LIKE '%arterial%o2%'
   OR LOWER(measurement_source_value) LIKE '%po2%art%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

-- 3. Urine Output
SELECT measurement_concept_id, measurement_source_value, COUNT(*) as n
FROM omopcdm.measurement
WHERE LOWER(measurement_source_value) LIKE '%urine%'
   OR LOWER(measurement_source_value) LIKE '%uo%'
   OR measurement_source_value ILIKE '%output%urine%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

-- Also check observation table
SELECT observation_concept_id, observation_source_value, COUNT(*) as n
FROM omopcdm.observation
WHERE LOWER(observation_source_value) LIKE '%urine%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

-- 4. Ventilation
SELECT procedure_concept_id, procedure_source_value, COUNT(*) as n
FROM omopcdm.procedure_occurrence
WHERE LOWER(procedure_source_value) LIKE '%vent%'
   OR LOWER(procedure_source_value) LIKE '%intubat%'
   OR LOWER(procedure_source_value) LIKE '%mech%vent%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

SELECT device_concept_id, device_source_value, COUNT(*) as n
FROM omopcdm.device_exposure
WHERE LOWER(device_source_value) LIKE '%vent%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

-- 5. Vasopressors (you found vasopressin)
SELECT drug_concept_id, drug_source_value, COUNT(*) as n
FROM omopcdm.drug_exposure
WHERE LOWER(drug_source_value) LIKE '%vasopressin%'
   OR LOWER(drug_source_value) LIKE '%vaso%'
GROUP BY 1,2 ORDER BY n DESC;

SELECT drug_concept_id, drug_source_value, COUNT(*) as n
FROM omopcdm.drug_exposure
WHERE LOWER(drug_source_value) LIKE '%norepi%'
   OR LOWER(drug_source_value) LIKE '%levophed%'
GROUP BY 1,2 ORDER BY n DESC;

SELECT drug_concept_id, drug_source_value, COUNT(*) as n
FROM omopcdm.drug_exposure
WHERE LOWER(drug_source_value) LIKE '%phenyl%'
GROUP BY 1,2 ORDER BY n DESC;

SELECT drug_concept_id, drug_source_value, COUNT(*) as n
FROM omopcdm.drug_exposure
WHERE LOWER(drug_source_value) LIKE '%dopamine%'
GROUP BY 1,2 ORDER BY n DESC;

-- 6. GCS and RASS
SELECT observation_concept_id, observation_source_value, COUNT(*) as n
FROM omopcdm.observation
WHERE LOWER(observation_source_value) LIKE '%gcs%'
   OR LOWER(observation_source_value) LIKE '%glasgow%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;

SELECT observation_concept_id, observation_source_value, COUNT(*) as n
FROM omopcdm.observation
WHERE LOWER(observation_source_value) LIKE '%rass%'
   OR LOWER(observation_source_value) LIKE '%sedation%'
GROUP BY 1,2 ORDER BY n DESC LIMIT 20;
