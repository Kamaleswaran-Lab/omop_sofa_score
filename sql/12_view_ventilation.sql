CREATE OR REPLACE VIEW results_site_a.vw_ventilation AS
SELECT DISTINCT vo.person_id, vo.visit_start_datetime AS charttime, TRUE AS ventilated
FROM omopcdm.device_exposure de
JOIN omopcdm.visit_occurrence vo ON de.visit_occurrence_id = vo.visit_occurrence_id
WHERE de.device_concept_id = 4222965
UNION
SELECT DISTINCT po.person_id, po.procedure_datetime AS charttime, TRUE
FROM omopcdm.procedure_occurrence po
WHERE po.procedure_concept_id IN (4202832, 42738694);