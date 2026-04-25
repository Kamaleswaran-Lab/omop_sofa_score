DROP TABLE IF EXISTS :results_schema.sepsis3_summary;
CREATE TABLE :results_schema.sepsis3_summary AS
SELECT COUNT(DISTINCT vd.person_id) AS icu_denominator,
  (SELECT COUNT(*) FROM :results_schema.sepsis3_enhanced_collapsed) AS enhanced_patients
FROM :cdm_schema.visit_detail vd WHERE vd.visit_detail_concept_id IN (32037,581379);
