
-- Compute each SOFA component with fixes
CREATE OR REPLACE VIEW results.v_sofa_components AS
WITH resp AS (
  SELECT p.person_id, p.dt,
         CASE WHEN p.val / NULLIF(f.val/100.0,0) < 100 THEN 4
              WHEN p.val / NULLIF(f.val/100.0,0) < 200 THEN 3
              WHEN p.val / NULLIF(f.val/100.0,0) < 300 THEN 2
              WHEN p.val / NULLIF(f.val/100.0,0) < 400 THEN 1 ELSE 0 END AS resp_score,
         p.val AS pao2, f.val AS fio2,
         EXTRACT(EPOCH FROM (f.dt - p.dt))/60 AS delta_min
  FROM results.v_lab p
  JOIN results.v_lab f ON p.person_id=f.person_id AND f.ancestor_concept_id=3013468 AND p.ancestor_concept_id=3002647
  AND ABS(EXTRACT(EPOCH FROM (f.dt - p.dt))/60) <= 240 -- FIX 3: 240 min window
  WHERE f.val IS NOT NULL -- FIX 2: no imputation
)
SELECT * FROM resp;
