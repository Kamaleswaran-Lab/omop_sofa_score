DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced;
CREATE TABLE :results_schema.sepsis3_enhanced AS
WITH onset AS (SELECT * FROM :results_schema.view_infection_onset_enhanced),
w AS (
  SELECT o.person_id, o.infection_onset, s.sofa_datetime, s.sofa_total,
    COALESCE(MIN(s.sofa_total) FILTER (WHERE s.sofa_datetime BETWEEN o.infection_onset - interval '72h' AND o.infection_onset - interval '24h') OVER (PARTITION BY o.person_id,o.infection_onset),0) AS baseline
  FROM onset o JOIN :results_schema.sofa_hourly s ON s.person_id=o.person_id AND s.sofa_datetime BETWEEN o.infection_onset - interval '72h' AND o.infection_onset + interval '48h'
)
SELECT person_id, infection_onset, sofa_datetime AS worst_time, sofa_total, baseline, sofa_total-baseline AS delta_sofa
FROM w WHERE sofa_total-baseline >=2 AND sofa_datetime BETWEEN infection_onset AND infection_onset + interval '48h';
