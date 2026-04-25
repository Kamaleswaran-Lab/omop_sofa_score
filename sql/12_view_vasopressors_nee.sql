-- Vasopressors with norepinephrine equivalent
-- FIX: include vasopressin 0.04 U/min = 1, epinephrine, dopamine
CREATE OR REPLACE VIEW :results_schema.view_vasopressors_nee AS
SELECT
  de.person_id,
  de.drug_exposure_start_datetime,
  de.drug_exposure_end_datetime,
  SUM(
    CASE
      WHEN ca.ancestor_concept_id = 1321342 THEN de.quantity -- norepi
      WHEN ca.ancestor_concept_id = 1319998 THEN de.quantity -- epi 1:1
      WHEN ca.ancestor_concept_id = 1321245 THEN de.quantity / 2 -- dopamine
      WHEN ca.ancestor_concept_id = 1319999 THEN de.quantity / 0.04 -- vasopressin
      ELSE 0
    END
  ) AS nee_mcg_kg_min
FROM :cdm_schema.drug_exposure de
JOIN :vocab_schema.concept_ancestor ca ON ca.descendant_concept_id = de.drug_concept_id
WHERE ca.ancestor_concept_id IN (1321342,1319998,1321245,1319999)
GROUP BY 1,2,3;
