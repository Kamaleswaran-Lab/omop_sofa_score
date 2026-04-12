
-- FIX 1 & 8: Vasopressin INCLUDED with NEE 2.5x, explicit unit normalization
CREATE OR REPLACE VIEW results.v_vasopressors AS
SELECT d.person_id, d.drug_exposure_start_datetime AS dt,
       d.drug_concept_id,
       CASE WHEN d.dose_unit_concept_id = 8749 THEN d.quantity / NULLIF(w.weight,0) -- mcg/min to mcg/kg/min
            WHEN d.dose_unit_concept_id = 8750 THEN d.quantity
            WHEN d.dose_unit_concept_id = 4118123 THEN d.quantity -- U/min for vasopressin
            ELSE d.quantity END AS dose_norm,
       CASE d.drug_concept_id
         WHEN 4328749 THEN 1.0 -- norepi
         WHEN 1338005 THEN 1.0 -- epi
         WHEN 1360635 THEN 2.5 -- vasopressin FIX: was excluded in v3.5
         WHEN 1335616 THEN 0.1 -- phenylephrine
         WHEN 1319998 THEN 0.01 -- dopamine
       END AS nee_factor,
       d.quantity * CASE d.drug_concept_id WHEN 1360635 THEN 2.5 WHEN 4328749 THEN 1.0 WHEN 1338005 THEN 1.0 WHEN 1335616 THEN 0.1 WHEN 1319998 THEN 0.01 END AS nee_contrib
FROM cdm.drug_exposure d
LEFT JOIN (SELECT person_id, value_as_number AS weight FROM cdm.measurement WHERE measurement_concept_id=3013762) w USING(person_id)
JOIN vocab.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id
WHERE ca.ancestor_concept_id IN (4328749,1338005,1360635,1335616,1319998);
