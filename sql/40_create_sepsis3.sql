-- Sepsis-3 strict - fixed baseline to MIN
DROP TABLE IF EXISTS :results_schema.sepsis3_cases CASCADE;
CREATE TABLE :results_schema.sepsis3_cases AS
WITH baseline AS (
  SELECT i.person_id, i.infection_onset,
         COALESCE(MIN(s.total_sofa),0) AS baseline_sofa
  FROM :results_schema.infection_onset i
  LEFT JOIN :results_schema.sofa_hourly s ON s.person_id=i.person_id AND s.charttime BETWEEN i.infection_onset - INTERVAL '72 hours' AND i.infection_onset - INTERVAL '1 hour'
  GROUP BY 1,2
),
peak AS (
  SELECT i.person_id, i.infection_onset,
         MAX(s.total_sofa) AS peak_sofa
  FROM :results_schema.infection_onset i
  JOIN :results_schema.sofa_hourly s ON s.person_id=i.person_id AND s.charttime BETWEEN i.infection_onset AND i.infection_onset + INTERVAL '48 hours'
  GROUP BY 1,2
)
SELECT b.person_id, b.infection_onset, b.baseline_sofa, p.peak_sofa, (p.peak_sofa - b.baseline_sofa) AS delta_sofa
FROM baseline b JOIN peak p USING(person_id, infection_onset)
WHERE (p.peak_sofa - b.baseline_sofa) >= 2;
