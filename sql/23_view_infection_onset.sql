-- OMOP SOFA v4.4 - Suspected infection onset
-- Sepsis-3 definition: antibiotics + culture within 72 hours

DROP VIEW IF EXISTS results.v_suspected_infection CASCADE;

CREATE VIEW results.v_suspected_infection AS
SELECT
    a.person_id,
    LEAST(a.abx_start, c.culture_time) AS infection_onset,
    a.abx_start,
    c.culture_time,
    ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time)) / 3600) AS hours_apart,
    a.antibiotic_name,
    c.culture_type,
    -- Determine which came first
    CASE 
        WHEN a.abx_start <= c.culture_time THEN 'antibiotics_first'
        ELSE 'culture_first'
    END AS order_of_events
FROM results.v_antibiotics a
JOIN results.v_cultures c 
    ON a.person_id = c.person_id
WHERE ABS(EXTRACT(EPOCH FROM (a.abx_start - c.culture_time)) / 3600) <= 72;

COMMENT ON VIEW results.v_suspected_infection IS 'Sepsis-3 suspected infection';

SELECT 'Infection onset view created' AS status;
