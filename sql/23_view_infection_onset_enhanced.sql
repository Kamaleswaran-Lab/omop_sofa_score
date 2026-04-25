-- Enhanced infection onset - v4.5 pragmatic
DROP VIEW IF EXISTS :results_schema.view_infection_onset_enhanced CASCADE;

CREATE OR REPLACE VIEW :results_schema.view_infection_onset_enhanced AS
WITH abx AS (
  SELECT de.person_id, de.visit_occurrence_id,
         COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS antibiotic_start,
         de.drug_concept_id,
         vd.visit_detail_concept_id
  FROM :cdm_schema.drug_exposure de
  JOIN :results_schema.assumptions a ON a.domain='antibiotic' AND a.concept_id = de.drug_concept_id
  LEFT JOIN :cdm_schema.visit_detail vd ON vd.visit_detail_id = de.visit_detail_id
),
abx_grouped AS (
  SELECT person_id, visit_occurrence_id, antibiotic_start,
         COUNT(DISTINCT drug_concept_id) OVER (PARTITION BY person_id, visit_occurrence_id ORDER BY antibiotic_start RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW) AS distinct_abx_24h,
         MAX(CASE WHEN vd_concept IN (SELECT concept_id FROM :results_schema.assumptions WHERE domain='icu') THEN 1 ELSE 0 END) AS icu_abx
  FROM (SELECT *, visit_detail_concept_id AS vd_concept FROM abx) x
),
cult AS (
  SELECT person_id, visit_occurrence_id,
         specimen_datetime AS culture_start
  FROM :results_schema.vw_cultures
),
paired AS (
  SELECT 
    COALESCE(a.person_id, c.person_id) AS person_id,
    COALESCE(a.visit_occurrence_id, c.visit_occurrence_id) AS visit_occurrence_id,
    a.antibiotic_start,
    c.culture_start,
    CASE WHEN a.antibiotic_start IS NOT NULL AND c.culture_start IS NOT NULL 
           AND ABS(EXTRACT(EPOCH FROM (a.antibiotic_start - c.culture_start))/3600) <= 96 THEN LEAST(a.antibiotic_start, c.culture_start)
         WHEN a.antibiotic_start IS NOT NULL AND (a.distinct_abx_24h >=2 OR a.icu_abx=1) THEN a.antibiotic_start
         ELSE NULL END AS infection_onset
  FROM abx_grouped a
  FULL OUTER JOIN cult c ON a.person_id=c.person_id AND a.visit_occurrence_id=c.visit_occurrence_id
    AND ABS(EXTRACT(EPOCH FROM (a.antibiotic_start - c.culture_start))/3600) <= 96
)
SELECT DISTINCT ON (person_id, visit_occurrence_id, infection_onset)
  person_id, visit_occurrence_id, infection_onset, antibiotic_start, culture_start
FROM paired
WHERE infection_onset IS NOT NULL
  AND infection_onset < CURRENT_DATE
ORDER BY person_id, visit_occurrence_id, infection_onset;
