
-- Sepsis-3 infection onset: abx + culture within 72h
CREATE OR REPLACE VIEW results.v_infection_onset AS
SELECT a.person_id, LEAST(a.abx_start, c.cx_time) AS infection_time
FROM results.v_antibiotics a
JOIN results.v_cultures c ON a.person_id=c.person_id
WHERE ABS(EXTRACT(EPOCH FROM (a.abx_start - c.cx_time))/3600) <= 72;
