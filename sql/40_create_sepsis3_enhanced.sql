-- Enhanced sepsis-3 - fixed
DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced CASCADE;
CREATE TABLE :results_schema.sepsis3_enhanced AS
WITH io AS (SELECT * FROM :results_schema.view_infection_onset_enhanced),
baseline AS (
  SELECT io.person_id, io.visit_occurrence_id, io.infection_onset,
         COALESCE(MIN(sh.total_sofa) FILTER (WHERE sh.charttime BETWEEN io.infection_onset - INTERVAL '72 hours' AND io.infection_onset - INTERVAL '1 hour'),0) AS baseline_sofa
  FROM io LEFT JOIN :results_schema.sofa_hourly sh ON sh.person_id=io.person_id AND sh.charttime BETWEEN io.infection_onset - INTERVAL '72 hours' AND io.infection_onset + INTERVAL '1 hour'
  GROUP BY 1,2,3
),
peak AS (
  SELECT io.person_id, io.visit_occurrence_id, io.infection_onset,
         MAX(sh.total_sofa) FILTER (WHERE sh.charttime BETWEEN io.infection_onset AND io.infection_onset + INTERVAL '48 hours') AS peak_sofa
  FROM io JOIN :results_schema.sofa_hourly sh ON sh.person_id=io.person_id AND sh.charttime BETWEEN io.infection_onset AND io.infection_onset + INTERVAL '48 hours'
  GROUP BY 1,2,3
)
SELECT b.*, p.peak_sofa, (p.peak_sofa - b.baseline_sofa) AS delta_sofa, (p.peak_sofa - b.baseline_sofa) >=2 AS meets_sepsis3
FROM baseline b JOIN peak p USING(person_id, visit_occurrence_id, infection_onset);
