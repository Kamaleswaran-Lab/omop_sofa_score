-- CORRECTED for MGH/CHoRUS: truncate to hour before joining to prevent fragmentation and memory blowup
DROP VIEW IF EXISTS {{results_schema}}.vw_sofa_components CASCADE;

CREATE OR REPLACE VIEW {{results_schema}}.vw_sofa_components AS
WITH labs AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MAX(pao2) AS pao2, MAX(fio2) AS fio2, MAX(pf_ratio) AS pf_ratio,
           MAX(bilirubin) AS bilirubin, MAX(creatinine) AS creatinine,
           MAX(platelets) AS platelets, MAX(lactate) AS lactate
    FROM {{results_schema}}.vw_labs_core
    GROUP BY 1,2
),
vitals AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MAX(map) AS map, MAX(sbp) AS sbp, MAX(dbp) AS dbp
    FROM {{results_schema}}.vw_vitals_core
    GROUP BY 1,2
),
vaso AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MAX(norepi_dose) AS norepi_dose, MAX(epi_dose) AS epi_dose,
           MAX(dopamine_dose) AS dopamine_dose, MAX(vasopressin_dose) AS vasopressin_dose
    FROM {{results_schema}}.vw_vasopressors_nee
    GROUP BY 1,2
),
vent AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MAX(ventilation_status) AS ventilation_status
    FROM {{results_schema}}.vw_ventilation
    GROUP BY 1,2
),
neuro AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MIN(gcs) AS gcs
    FROM {{results_schema}}.vw_neuro
    GROUP BY 1,2
),
urine AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           SUM(urine_output) AS urine_output
    FROM {{results_schema}}.vw_urine_24h
    GROUP BY 1,2
),
rrt AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MAX(rrt_status) AS rrt_status
    FROM {{results_schema}}.vw_rrt
    GROUP BY 1,2
)
SELECT
    COALESCE(l.person_id, v.person_id, vaso.person_id, vent.person_id, neuro.person_id, urine.person_id, rrt.person_id) AS person_id,
    COALESCE(l.hr, v.hr, vaso.hr, vent.hr, neuro.hr, urine.hr, rrt.hr) AS charttime,
    l.pao2, l.fio2, l.pf_ratio, l.bilirubin, l.creatinine, l.platelets, l.lactate,
    v.map, v.sbp, v.dbp,
    vaso.norepi_dose, vaso.epi_dose, vaso.dopamine_dose, vaso.vasopressin_dose,
    vent.ventilation_status,
    neuro.gcs,
    urine.urine_output,
    rrt.rrt_status
FROM labs l
FULL OUTER JOIN vitals v USING (person_id, hr)
FULL OUTER JOIN vaso USING (person_id, hr)
FULL OUTER JOIN vent USING (person_id, hr)
FULL OUTER JOIN neuro USING (person_id, hr)
FULL OUTER JOIN urine USING (person_id, hr)
FULL OUTER JOIN rrt USING (person_id, hr);
