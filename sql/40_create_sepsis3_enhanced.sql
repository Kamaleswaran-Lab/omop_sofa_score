-- v4.5 Sepsis-3 enhanced (pragmatic)
DROP TABLE IF EXISTS {{results_schema}}.sepsis3_enhanced CASCADE;

CREATE TABLE {{results_schema}}.sepsis3_enhanced AS
SELECT
    i.person_id,
    i.infection_onset,
    i.infection_type,
    i.icu_onset,
    i.distinct_abx_count,
    i.total_abx_days,
    i.has_culture,
    MIN(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.baseline_start AND i.infection_onset) AS baseline_sofa,
    MAX(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.infection_onset AND i.organ_dysfunction_end) AS peak_sofa,
    MAX(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.infection_onset AND i.organ_dysfunction_end) -
    MIN(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.baseline_start AND i.infection_onset) AS delta_sofa
FROM {{results_schema}}.view_infection_onset_enhanced i
LEFT JOIN {{results_schema}}.sofa_hourly s
  ON s.person_id = i.person_id
GROUP BY 1,2,3,4,5,6,7
HAVING MAX(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.infection_onset AND i.organ_dysfunction_end) -
       MIN(s.total_sofa) FILTER (WHERE s.charttime BETWEEN i.baseline_start AND i.infection_onset) >= 2;

CREATE INDEX idx_sepsis3_enh_person ON {{results_schema}}.sepsis3_enhanced(person_id);
CREATE INDEX idx_sepsis3_enh_onset ON {{results_schema}}.sepsis3_enhanced(infection_onset);
CREATE INDEX idx_sepsis3_enh_icu ON {{results_schema}}.sepsis3_enhanced(icu_onset);
