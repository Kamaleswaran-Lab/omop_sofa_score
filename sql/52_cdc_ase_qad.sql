-- Fix: Proper lag-based gap logic to accurately respect the 1-day allowance
DROP TABLE IF EXISTS :results_schema.ase_qad CASCADE;
CREATE TABLE :results_schema.ase_qad AS
WITH abx_days AS (
  SELECT DISTINCT 
    de.person_id, 
    COALESCE(de.drug_exposure_start_datetime::date, de.drug_exposure_start_date) AS abx_day
  FROM :cdm_schema.drug_exposure de
  JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
  WHERE ca.ancestor_concept_id = 21602796 -- Antibacterials
),
ordered_days AS (
  SELECT *,
    LAG(abx_day) OVER (PARTITION BY person_id ORDER BY abx_day) AS prev_day
  FROM abx_days
),
course_flags AS (
  SELECT *,
    CASE WHEN prev_day IS NULL 
           OR abx_day - prev_day > (SELECT qad_max_gap_days + 1 FROM :results_schema.ase_parameters)
         THEN 1 ELSE 0 END AS is_new_course
  FROM ordered_days
),
course_ids AS (
  SELECT *,
    SUM(is_new_course) OVER (PARTITION BY person_id ORDER BY abx_day) AS course_id
  FROM course_flags
)
SELECT person_id, MIN(abx_day) AS qad_start, MAX(abx_day) AS qad_end, COUNT(*) AS qad_days
FROM course_ids
GROUP BY person_id, course_id
HAVING COUNT(*) >= (SELECT qad_min_days FROM :results_schema.ase_parameters);
