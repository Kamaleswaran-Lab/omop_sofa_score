-- 54_cdc_ase_cases.sql
-- PURPOSE: Combine infection (culture + QAD) with organ dysfunction

DROP TABLE IF EXISTS omop_cdm.ase_cases CASCADE;
CREATE TABLE omop_cdm.ase_cases AS
SELECT
  od.person_id,
  od.visit_occurrence_id,
  od.culture_datetime AS infection_onset,
  qad.qad_start,
  qad.qad_end
FROM omop_cdm.ase_organ_dysfunction od
JOIN omop_cdm.ase_qad qad
  ON qad.person_id = od.person_id
 AND qad.visit_occurrence_id = od.visit_occurrence_id
 AND qad.qad_start BETWEEN od.culture_datetime - INTERVAL '2 days'
                       AND od.culture_datetime + INTERVAL '2 days'
WHERE (od.vaso_init OR od.vent_init OR od.lactate_high) -- add other criteria as needed
;
