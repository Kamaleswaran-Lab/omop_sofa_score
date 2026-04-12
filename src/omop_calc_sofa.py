"""
omop_calc_sofa.py v3.5 - All fixes applied
"""

import pandas as pd
import numpy as np
from omop_utils import fetch, sql_concept_set, sql_vasopressors, sql_ventilation, sql_map_derived, apply_dq_filters, convert, get_connection, return_connection
from config import CLINICAL_SCHEMA, VOCAB_SCHEMA, PAO2_FIO2_WINDOW, SPO2_FIO2_WINDOW, FIO2_IMPUTATION, RESULTS_SCHEMA, CODE_VERSION

def compute_hourly_sofa(conn, person_ids=None):
    pf_sec = PAO2_FIO2_WINDOW * 60
    sf_sec = SPO2_FIO2_WINDOW * 60
    filt = f"AND vo.person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    
    sql = f"""
WITH visits AS (
  SELECT person_id, visit_occurrence_id, visit_start_datetime AS vs, visit_end_datetime AS ve
  FROM {CLINICAL_SCHEMA}.visit_occurrence vo
  WHERE visit_concept_id IN (32037, 32038, 262) {filt}
),
grid AS (
  SELECT person_id, visit_occurrence_id, generate_series(date_trunc('hour', vs), date_trunc('hour', ve), interval '1 hour') AS ts
  FROM visits
),
pao2 AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('pao2')}) {filt.replace('vo.', '')}),
fio2 AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('fio2')}) {filt.replace('vo.', '')}),
spo2 AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('spo2')}) {filt.replace('vo.', '')}),
pf AS (SELECT p.person_id, p.visit_occurrence_id, p.ts, p.v AS pao2, p.u AS pu, f.v AS fio2, f.u AS fu FROM pao2 p LEFT JOIN LATERAL (SELECT v, u FROM fio2 f WHERE f.person_id = p.person_id AND f.visit_occurrence_id = p.visit_occurrence_id AND abs(extract(epoch FROM f.ts - p.ts)) <= {pf_sec} ORDER BY abs(extract(epoch FROM f.ts - p.ts)) LIMIT 1) f ON true),
sf AS (SELECT s.person_id, s.visit_occurrence_id, s.ts, s.v AS spo2, s.u AS su, f.v AS fio2, f.u AS fu FROM spo2 s LEFT JOIN LATERAL (SELECT v, u FROM fio2 f WHERE f.person_id = s.person_id AND f.visit_occurrence_id = s.visit_occurrence_id AND abs(extract(epoch FROM f.ts - s.ts)) <= {sf_sec} ORDER BY abs(extract(epoch FROM f.ts - s.ts)) LIMIT 1) f ON true WHERE s.v <= 97),
vent AS ({sql_ventilation(person_ids)}),
bili AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('bilirubin')}) {filt.replace('vo.', '')}),
creat AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('creatinine')}) {filt.replace('vo.', '')}),
plt AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('platelets')}) {filt.replace('vo.', '')}),
mapv AS ({sql_map_derived(person_ids)}),
gcs AS (
  SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts,
         MAX(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_total')}) THEN value_as_number END) AS gcs_total,
         MAX(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_eye')}) THEN value_as_number END) AS gcs_e,
         MAX(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_verbal')}) THEN value_as_number END) AS gcs_v,
         MAX(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_motor')}) THEN value_as_number END) AS gcs_m
  FROM {CLINICAL_SCHEMA}.measurement
  WHERE measurement_concept_id IN ({sql_concept_set('gcs_total')}) OR measurement_concept_id IN ({sql_concept_set('gcs_eye')}) OR measurement_concept_id IN ({sql_concept_set('gcs_verbal')}) OR measurement_concept_id IN ({sql_concept_set('gcs_motor')})
  {filt.replace('vo.', '')} GROUP BY 1,2,3
),
vaso AS ({sql_vasopressors(person_ids)}),
rrt AS (SELECT person_id, visit_occurrence_id, COALESCE(procedure_datetime, procedure_date) AS t FROM {CLINICAL_SCHEMA}.procedure_occurrence WHERE procedure_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id = 4146536) {filt.replace('vo.', '')}),
uo AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('urine')}) {filt.replace('vo.', '')})
SELECT g.person_id, g.visit_occurrence_id, g.ts,
 (SELECT v FROM bili b WHERE b.person_id = g.person_id AND b.visit_occurrence_id = g.visit_occurrence_id AND b.ts <= g.ts AND b.ts > g.ts - interval '24 hours' ORDER BY b.ts DESC LIMIT 1) AS bv,
 (SELECT u FROM bili b WHERE b.person_id = g.person_id AND b.visit_occurrence_id = g.visit_occurrence_id AND b.ts <= g.ts AND b.ts > g.ts - interval '24 hours' ORDER BY b.ts DESC LIMIT 1) AS bu,
 (SELECT v FROM creat c WHERE c.person_id = g.person_id AND c.visit_occurrence_id = g.visit_occurrence_id AND c.ts <= g.ts AND c.ts > g.ts - interval '24 hours' ORDER BY c.ts DESC LIMIT 1) AS cv,
 (SELECT u FROM creat c WHERE c.person_id = g.person_id AND c.visit_occurrence_id = g.visit_occurrence_id AND c.ts <= g.ts AND c.ts > g.ts - interval '24 hours' ORDER BY c.ts DESC LIMIT 1) AS cu,
 (SELECT v FROM plt p WHERE p.person_id = g.person_id AND p.visit_occurrence_id = g.visit_occurrence_id AND p.ts <= g.ts AND p.ts > g.ts - interval '24 hours' ORDER BY p.ts DESC LIMIT 1) AS pv,
 (SELECT map FROM mapv m WHERE m.person_id = g.person_id AND m.visit_occurrence_id = g.visit_occurrence_id AND m.ts <= g.ts AND m.ts > g.ts - interval '2 hours' ORDER BY m.ts DESC LIMIT 1) AS mv,
 (SELECT map_source FROM mapv m WHERE m.person_id = g.person_id AND m.visit_occurrence_id = g.visit_occurrence_id AND m.ts <= g.ts AND m.ts > g.ts - interval '2 hours' ORDER BY m.ts DESC LIMIT 1) AS mv_src,
 (SELECT gcs_total FROM gcs WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS gcs_t,
 (SELECT gcs_e FROM gcs WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS gcs_e,
 (SELECT gcs_v FROM gcs WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS gcs_v,
 (SELECT gcs_m FROM gcs WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS gcs_m,
 (SELECT pao2 FROM pf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS pao2v,
 (SELECT pu FROM pf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS pao2u,
 (SELECT fio2 FROM pf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS fio2v,
 (SELECT fu FROM pf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS fio2u,
 (SELECT spo2 FROM sf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS spo2v,
 (SELECT su FROM sf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS spo2u,
 (SELECT fio2 FROM sf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS sfio2v,
 (SELECT fu FROM sf WHERE person_id = g.person_id AND visit_occurrence_id = g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS sfio2u,
 EXISTS(SELECT 1 FROM vent v WHERE v.person_id = g.person_id AND v.visit_occurrence_id = g.visit_occurrence_id AND g.ts BETWEEN v.s AND v.e) AS vent,
 EXISTS(SELECT 1 FROM rrt r WHERE r.person_id = g.person_id AND r.visit_occurrence_id = g.visit_occurrence_id AND abs(extract(epoch FROM r.t - g.ts)) <= 43200) AS rrt,
 (SELECT SUM(v) FROM uo u WHERE u.person_id = g.person_id AND u.visit_occurrence_id = g.visit_occurrence_id AND u.ts > g.ts - interval '24 hours' AND u.ts <= g.ts) AS uo24_raw,
 (SELECT u FROM uo u WHERE u.person_id = g.person_id AND u.visit_occurrence_id = g.visit_occurrence_id AND u.ts > g.ts - interval '24 hours' AND u.ts <= g.ts ORDER BY u.ts DESC LIMIT 1) AS uo_u,
 (SELECT SUM(rate * norepi_factor) FROM vaso vs WHERE vs.person_id = g.person_id AND vs.visit_occurrence_id = g.visit_occurrence_id AND g.ts BETWEEN vs.s AND vs.e) AS ne,
 (SELECT rate_source FROM vaso vs WHERE vs.person_id = g.person_id AND vs.visit_occurrence_id = g.visit_occurrence_id AND g.ts BETWEEN vs.s AND vs.e ORDER BY vs.s DESC LIMIT 1) AS ne_src
FROM grid g
"""
    df = fetch(conn, sql)
    
    # Apply conversions
    df['bili'] = df.apply(lambda r: convert(r.bv, 'bilirubin', r.bu), axis=1)
    df['creat'] = df.apply(lambda r: convert(r.cv, 'creatinine', r.cu), axis=1)
    df['pao2'] = df.apply(lambda r: convert(r.pao2v, 'pao2', r.pao2u), axis=1)
    df['fio2'] = df.apply(lambda r: convert(r.fio2v, 'fio2', r.fio2u), axis=1)
    df['spo2'] = df.apply(lambda r: convert(r.spo2v, 'spo2', r.spo2u), axis=1)
    df['sfio2'] = df.apply(lambda r: convert(r.sfio2v, 'fio2', r.sfio2u), axis=1)
    df['uo24'] = df.apply(lambda r: convert(r.uo24_raw, 'urine', r.uo_u), axis=1)
    
    # Data quality filters
    df = apply_dq_filters(df)
    
    # FiO2 imputation
    df['fio2_imp'] = df['fio2']
    df['fio2_imp_method'] = 'none'
    if FIO2_IMPUTATION == "conditional":
        mask_vent = df['fio2'].isna() & df['vent']
        df.loc[mask_vent, 'fio2_imp'] = 0.6
        df.loc[mask_vent, 'fio2_imp_method'] = 'vent_assumed_60'
        mask_room = df['fio2'].isna() & ~df['vent']
        df.loc[mask_room, 'fio2_imp'] = 0.21
        df.loc[mask_room, 'fio2_imp_method'] = 'room_air_21'
    
    df['pf'] = df['pao2'] / df['fio2_imp'].replace(0, np.nan)
    df['sf'] = np.where(df['spo2'] <= 0.97, df['spo2'] / df['sfio2'].replace(0, np.nan), np.nan)
    df['sf_eq'] = (df['sf'] * 100 - 64) / 0.84
    
    # GCS with intubation handling
    def calc_gcs(row):
        if pd.notna(row.gcs_t):
            return row.gcs_t
        if pd.notna(row.gcs_e) and pd.notna(row.gcs_m):
            # If intubated (vent) and verbal missing, use modified
            if row.vent and pd.isna(row.gcs_v):
                return row.gcs_e + 1 + row.gcs_m  # Assume verbal=1T
            if pd.notna(row.gcs_v):
                return row.gcs_e + row.gcs_v + row.gcs_m
        return np.nan
    
    df['gcs_calc'] = df.apply(calc_gcs, axis=1)
    
    # SOFA scores
    def resp_score(r):
        val = r.pf if pd.notna(r.pf) else r.sf_eq
        if pd.isna(val):
            return np.nan
        if val >= 400:
            return 0
        if val >= 300:
            return 1
        if val >= 200:
            return 2
        if r.vent:
            return 3 if val >= 100 else 4
        return 2 if val >= 100 else 3
    
    df['resp'] = df.apply(resp_score, axis=1)
    df['cardio'] = df.apply(lambda r: 3 if pd.notna(r.ne) and r.ne <= 0.1 else 4 if pd.notna(r.ne) and r.ne > 0.1 else (0 if r.mv >= 70 else 1) if pd.notna(r.mv) else np.nan, axis=1)
    df['neuro'] = df['gcs_calc'].apply(lambda x: 0 if x >= 15 else 1 if x >= 13 else 2 if x >= 10 else 3 if x >= 6 else 4 if pd.notna(x) else np.nan)
    df['hepatic'] = df['bili'].apply(lambda x: 0 if x < 1.2 else 1 if x < 2 else 2 if x < 6 else 3 if x < 12 else 4 if pd.notna(x) else np.nan)
    df['renal'] = df.apply(lambda r: 4 if r.rrt else (4 if r.uo24 < 200 else 3 if r.uo24 < 500 else np.nan) if pd.notna(r.uo24) else (0 if r.creat < 1.2 else 1 if r.creat < 2 else 2 if r.creat < 3.5 else 3 if r.creat < 5 else 4) if pd.notna(r.creat) else np.nan, axis=1)
    df['coag'] = df['pv'].apply(lambda x: 0 if x >= 150 else 1 if x >= 100 else 2 if x >= 50 else 3 if x >= 20 else 4 if pd.notna(x) else np.nan)
    df['total'] = df[['resp', 'cardio', 'neuro', 'hepatic', 'renal', 'coag']].sum(axis=1, min_count=4)
    df['code_version'] = CODE_VERSION
    
    return df[['person_id', 'visit_occurrence_id', 'ts', 'total', 'resp', 'cardio', 'neuro', 'hepatic', 'renal', 'coag', 'pf', 'sf_eq', 'ne', 'ne_src', 'mv', 'mv_src', 'fio2_imp_method', 'vent', 'code_version']].rename(columns={'ts': 'charttime'})
