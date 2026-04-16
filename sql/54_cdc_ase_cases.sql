DROP TABLE IF EXISTS :results_schema.ase_cases CASCADE;
CREATE TABLE :results_schema.ase_cases AS
SELECT
  od.person_id,
  od.culture_datetime AS infection_onset,
  qad.qad_start,
  qad.qad_end
FROM :results_schema.ase_organ_dysfunction od
JOIN :results_schema.ase_qad qad
  ON qad.person_id = od.person_id
 AND qad.qad_start BETWEEN (od.culture_datetime::date - INTERVAL '2 days')::date
                       AND (od.culture_datetime::date + INTERVAL '2 days')::date
WHERE (od.vaso_init OR od.vent_init OR od.lactate_high);
