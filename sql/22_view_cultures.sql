-- Blood and sterile cultures
CREATE OR REPLACE VIEW :results_schema.view_cultures AS
SELECT
  s.person_id,
  s.specimen_datetime,
  s.specimen_concept_id
FROM :cdm_schema.specimen s
WHERE s.specimen_concept_id IN (4048479, 4051875); -- blood culture examples
