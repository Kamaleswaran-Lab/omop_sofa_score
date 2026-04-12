
-- FIX 6: rolling 24h urine
CREATE OR REPLACE VIEW results.v_urine_24h AS
SELECT person_id, dt,
       SUM(val) OVER (PARTITION BY person_id ORDER BY dt RANGE BETWEEN INTERVAL '24 hours' PRECEDING AND CURRENT ROW) AS urine_24h
FROM results.v_lab WHERE ancestor_concept_id=4065485;
