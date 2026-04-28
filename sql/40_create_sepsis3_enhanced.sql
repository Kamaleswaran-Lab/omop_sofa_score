-- sql/40_create_sepsis3_enhanced.sql
-- DEPENDS ON: 23_view_infection_onset_enhanced.sql, 31 (sofa_hourly from vw_sofa_components)
-- PURPOSE: Join infection onset with pre-computed sofa_hourly; no lab/vital recalculation

DROP TABLE IF EXISTS :results_schema.sepsis3_windows CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced CASCADE;
DROP TABLE IF EXISTS :results_schema.sepsis3_cohort CASCADE;

-- 1) Windows around infection (Sepsis-3: -48h to +24h)
CREATE TABLE :results_schema.sepsis3_windows AS
SELECT
  io.person_id,
  io.infection_onset,
  io.antibiotic_time,
  io.culture_time,
  io.hours_apart,
  io.drug_exposure_id,
  io.specimen_id,
  io.visit_occurrence_id,
  (io.infection_onset - INTERVAL '48 hours') AS window_start,
  (io.infection_onset + INTERVAL '24 hours') AS window_end,
  (io.infection_onset - INTERVAL '24 hours') AS baseline_start
FROM :results_schema.view_infection_onset io;

CREATE INDEX ON :results_schema.sepsis3_windows(person_id, infection_onset);

-- 2) Pull SOFA from existing sofa_hourly
CREATE TABLE :results_schema.sepsis3_enhanced AS
WITH baseline AS (
  SELECT
    w.person_id,
    w.infection_onset,
    COALESCE(MIN(sh.sofa_total) FILTER (WHERE sh.hr BETWEEN w.baseline_start AND w.infection_onset), 0) AS sofa_baseline
  FROM :results_schema.sepsis3_windows w
  LEFT JOIN :results_schema.sofa_hourly sh
    ON sh.person_id = w.person_id
   AND sh.hr BETWEEN w.baseline_start AND w.infection_onset
  GROUP BY 1,2
),
worst AS (
  SELECT DISTINCT ON (w.person_id, w.infection_onset)
    w.person_id,
    w.infection_onset,
    sh.hr AS sofa_worst_time,
    sh.sofa_total AS sofa_max,
    sh.sofa_respiration,
    sh.sofa_coagulation,
    sh.sofa_liver,
    sh.sofa_cardiovascular,
    sh.sofa_cns,
    sh.sofa_renal
  FROM :results_schema.sepsis3_windows w
  JOIN :results_schema.sofa_hourly sh
    ON sh.person_id = w.person_id
   AND sh.hr BETWEEN w.window_start AND w.window_end
  ORDER BY w.person_id, w.infection_onset, sh.sofa_total DESC, sh.hr ASC
)
SELECT
  w.person_id,
  w.infection_onset,
  w.antibiotic_time,
  w.culture_time,
  w.window_start,
  w.window_end,
  b.sofa_baseline,
  ws.sofa_max,
  ws.sofa_worst_time,
  (ws.sofa_max - b.sofa_baseline) AS sofa_delta,
  ws.sofa_respiration,
  ws.sofa_coagulation,
  ws.sofa_liver,
  ws.sofa_cardiovascular,
  ws.sofa_cns,
  ws.sofa_renal,
  (ws.sofa_max - b.sofa_baseline) >= 2 AS meets_sepsis3,
  w.drug_exposure_id,
  w.specimen_id,
  w.visit_occurrence_id
FROM :results_schema.sepsis3_windows w
LEFT JOIN baseline b USING (person_id, infection_onset)
LEFT JOIN worst ws USING (person_id, infection_onset)
WHERE ws.sofa_max IS NOT NULL;

CREATE INDEX ON :results_schema.sepsis3_enhanced(person_id, infection_onset);

-- 3) Final Sepsis-3 cohort: first qualifying episode per patient
CREATE TABLE :results_schema.sepsis3_cohort AS
SELECT DISTINCT ON (person_id)
  person_id,
  infection_onset AS sepsis_onset,
  antibiotic_time,
  culture_time,
  sofa_baseline,
  sofa_max AS sofa_total,
  sofa_delta,
  sofa_worst_time,
  sofa_respiration,
  sofa_coagulation,
  sofa_liver,
  sofa_cardiovascular,
  sofa_cns,
  sofa_renal,
  drug_exposure_id,
  specimen_id,
  visit_occurrence_id
FROM :results_schema.sepsis3_enhanced
WHERE meets_sepsis3
ORDER BY person_id, infection_onset;

CREATE INDEX ON :results_schema.sepsis3_cohort(person_id);
CREATE INDEX ON :results_schema.sepsis3_cohort(sepsis_onset);

COMMENT ON TABLE :results_schema.sepsis3_cohort IS 'Sepsis-3 cohort built from view_infection_onset (474k pairs) joined to pre-computed sofa_hourly from vw_sofa_components.';

-- Validation
SELECT 'sepsis3_enhanced' AS tbl, COUNT(*) FROM :results_schema.sepsis3_enhanced
UNION ALL
SELECT 'sepsis3_cohort', COUNT(*) FROM :results_schema.sepsis3_cohort;
