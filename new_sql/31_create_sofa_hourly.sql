-- Calculate hourly SOFA - corrected thresholds
DROP TABLE IF EXISTS :results_schema.sofa_hourly CASCADE;

CREATE TABLE :results_schema.sofa_hourly AS
SELECT sc.person_id, sc.charttime,
  CASE WHEN sc.pf_ratio >=400 THEN 0 WHEN sc.pf_ratio >=300 THEN 1 WHEN sc.pf_ratio >=200 THEN 2 
       WHEN sc.pf_ratio >=100 AND sc.ventilation_status THEN 3 
       WHEN sc.pf_ratio <100 AND sc.ventilation_status THEN 4 
       WHEN sc.pf_ratio IS NOT NULL THEN 2 ELSE NULL END AS resp_sofa,
  CASE WHEN sc.nee_dose >0.1 THEN 4 WHEN sc.nee_dose >0 THEN 3 WHEN sc.map <70 THEN 1 ELSE 0 END AS cardio_sofa,
  CASE WHEN sc.gcs >=15 THEN 0 WHEN sc.gcs >=13 THEN 1 WHEN sc.gcs >=10 THEN 2 WHEN sc.gcs >=6 THEN 3 WHEN sc.gcs <6 THEN 4 ELSE NULL END AS neuro_sofa,
  CASE WHEN sc.rrt_status THEN 4 WHEN sc.creatinine >=5.0 THEN 4 WHEN sc.creatinine >=3.5 THEN 3 WHEN sc.creatinine >=2.0 THEN 2 WHEN sc.creatinine >=1.2 THEN 1 WHEN sc.creatinine <1.2 THEN 0 ELSE NULL END AS renal_sofa,
  CASE WHEN sc.bilirubin >=12 THEN 4 WHEN sc.bilirubin >=6 THEN 3 WHEN sc.bilirubin >=2 THEN 2 WHEN sc.bilirubin >=1.2 THEN 1 WHEN sc.bilirubin <1.2 THEN 0 ELSE NULL END AS hepatic_sofa,
  CASE WHEN sc.platelets >=150 THEN 0 WHEN sc.platelets >=100 THEN 1 WHEN sc.platelets >=50 THEN 2 WHEN sc.platelets >=20 THEN 3 WHEN sc.platelets <20 THEN 4 ELSE NULL END AS coag_sofa,
  sc.*
FROM :results_schema.vw_sofa_components sc;

ALTER TABLE :results_schema.sofa_hourly ADD COLUMN total_sofa INTEGER;
UPDATE :results_schema.sofa_hourly SET total_sofa = COALESCE(resp_sofa,0)+COALESCE(cardio_sofa,0)+COALESCE(neuro_sofa,0)+COALESCE(renal_sofa,0)+COALESCE(hepatic_sofa,0)+COALESCE(coag_sofa,0);
CREATE INDEX ON :results_schema.sofa_hourly(person_id, charttime);
