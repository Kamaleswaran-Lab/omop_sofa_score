
-- Hourly grid per ICU visit
CREATE OR REPLACE VIEW results.v_sofa_hourly AS
SELECT v.person_id, v.visit_occurrence_id, gs.hr AS charttime
FROM cdm.visit_occurrence v
CROSS JOIN generate_series(v.visit_start_datetime, v.visit_end_datetime, interval '1 hour') gs(hr)
WHERE v.visit_concept_id = 32037;
