-- CORRECTED for MGH/CHoRUS: vw_labs_core lacks pao2/fio2; vw_vasopressors_nee lacks epi/dopamine/vaso
DROP VIEW IF EXISTS {{results_schema}}.vw_sofa_components CASCADE;

CREATE OR REPLACE VIEW {{results_schema}}.vw_sofa_components AS
WITH labs_core AS (
    SELECT person_id, date_trunc('hour', charttime) AS hr,
           MAX(creatinine) AS creatinine,
           MAX(bilirubin) AS bilirubin,
           MAX(platelets) AS platelets,
           MAX(lactate) AS lactate
    FROM {{results_schema}}.vw_labs_core
    GROUP BY 1,2
),
pao2fio2 AS (
    SELECT person_id, date_trunc('hour', pao2_time) AS hr,
           MAX(pao2) AS pao2,
           MAX(fio2) AS fio2,
           MAX(pf_ratio) AS pf_ratio
    FROM {{results_schema}}.vw_pao2_fio2_pairs
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
           MAX(norepi_dose) AS norepi_dose,
           MAX(nee_dose) AS nee_dose
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
    COALESCE(lc.person_id, pf.person_id, v.person_id, vaso.person_id, vent.person_id, neuro.person_id, urine.person_id, rrt.person_id) AS person_id,
    COALESCE(lc.hr, pf.hr, v.hr, vaso.hr, vent.hr, neuro.hr, urine.hr, rrt.hr) AS charttime,
    pf.pao2, pf.fio2, pf.pf_ratio,
    lc.bilirubin, lc.creatinine, lc.platelets, lc.lactate,
    v.map, v.sbp, v.dbp,
    vaso.norepi_dose, vaso.nee_dose,
    NULL::numeric AS epi_dose,
    NULL::numeric AS dopamine_dose,
    NULL::numeric AS vasopressin_dose,
    vent.ventilation_status,
    neuro.gcs,
    urine.urine_output,
    rrt.rrt_status
FROM labs_core lc
FULL OUTER JOIN pao2fio2 pf USING (person_id, hr)
FULL OUTER JOIN vitals v USING (person_id, hr)
FULL OUTER JOIN vaso USING (person_id, hr)
FULL OUTER JOIN vent USING (person_id, hr)
FULL OUTER JOIN neuro USING (person_id, hr)
FULL OUTER JOIN urine USING (person_id, hr)
FULL OUTER JOIN rrt USING (person_id, hr);
