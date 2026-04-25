DROP TABLE IF EXISTS :results_schema.sepsis3_enhanced_collapsed;
CREATE TABLE :results_schema.sepsis3_enhanced_collapsed AS
WITH o AS (SELECT *, LAG(infection_onset) OVER (PARTITION BY person_id ORDER BY infection_onset) prev FROM :results_schema.sepsis3_enhanced),
g AS (SELECT *, SUM(CASE WHEN prev IS NULL OR infection_onset-prev > interval '48h' THEN 1 ELSE 0 END) OVER (PARTITION BY person_id ORDER BY infection_onset) grp FROM o)
SELECT person_id, MIN(infection_onset) infection_onset, MAX(delta_sofa) max_delta_sofa
FROM g GROUP BY person_id, grp;
