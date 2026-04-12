"""
omop_calc_sofa.py - Hourly and Daily SOFA
v3.1: PaO2/FiO2 window 120 min, SpO2/FiO2 surrogate added, all SQL
"""

import pandas as pd
import numpy as np
from omop_utils import (
    fetch_sql, sql_concept_set, sql_vasopressors, sql_ventilation, sql_rrt,
    CLINICAL_SCHEMA, VOCAB_SCHEMA, PAO2_FIO2_WINDOW_MIN, SPO2_FIO2_WINDOW_MIN, convert
)

def _resp_score(pf, sf, vent):
    val = pf if pd.notna(pf) else sf
    if pd.isna(val): return np.nan
    if val >= 400: return 0
    if val >= 300: return 1
    if val >= 200: return 2
    if vent: return 3 if val >= 100 else 4
    return 2 if val >= 100 else 3

def _cardio(map_v, norepi):
    if pd.notna(norepi) and norepi>0: return 3 if norepi<=0.1 else 4
    if pd.isna(map_v): return np.nan
    return 0 if map_v>=70 else 1

def _neuro(gcs):
    if pd.isna(gcs): return np.nan
    return 0 if gcs>=15 else 1 if gcs>=13 else 2 if gcs>=10 else 3 if gcs>=6 else 4

def _hepatic(b):
    if pd.isna(b): return np.nan
    return 0 if b<1.2 else 1 if b<2 else 2 if b<6 else 3 if b<12 else 4

def _renal(cr, uo, rrt):
    if rrt: return 4
    if pd.notna(uo):
        if uo<200: return 4
        if uo<500: return 3
    if pd.isna(cr): return np.nan
    return 0 if cr<1.2 else 1 if cr<2 else 2 if cr<3.5 else 3 if cr<5 else 4

def _coag(p):
    if pd.isna(p): return np.nan
    return 0 if p>=150 else 1 if p>=100 else 2 if p>=50 else 3 if p>=20 else 4

def compute_hourly_sofa(db_conn, person_ids=None, pf_window=PAO2_FIO2_WINDOW_MIN, sf_window=SPO2_FIO2_WINDOW_MIN):
    filt = f"AND person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    pf_sec = pf_window*60
    sf_sec = sf_window*60
    
    sql = f"""
WITH grid AS (
  SELECT person_id, visit_occurrence_id,
         generate_series(date_trunc('hour', MIN(ts)), date_trunc('hour', MAX(ts)), interval '1 hour') AS ts
  FROM (
    SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts
    FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('pao2')})
    UNION ALL SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('creatinine')})
  ) u WHERE 1=1 {filt} GROUP BY 1,2
),
pao2 AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('pao2')}) {filt}),
fio2 AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('fio2')}) {filt}),
spo2 AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('spo2')}) {filt}),
pf_pair AS (
  SELECT p.person_id, p.visit_occurrence_id, p.ts,
         p.v AS pao2, p.u AS pao2_u,
         f.v AS fio2, f.u AS fio2_u
  FROM pao2 p LEFT JOIN LATERAL (
    SELECT v,u FROM fio2 f WHERE f.person_id=p.person_id AND f.visit_occurrence_id=p.visit_occurrence_id
      AND abs(extract(epoch FROM f.ts-p.ts)) <= {pf_sec} ORDER BY abs(extract(epoch FROM f.ts-p.ts)) LIMIT 1
  ) f ON true
),
sf_pair AS (
  SELECT s.person_id, s.visit_occurrence_id, s.ts,
         s.v AS spo2, s.u AS spo2_u,
         f.v AS fio2, f.u AS fio2_u
  FROM spo2 s LEFT JOIN LATERAL (
    SELECT v,u FROM fio2 f WHERE f.person_id=s.person_id AND f.visit_occurrence_id=s.visit_occurrence_id
      AND abs(extract(epoch FROM f.ts-s.ts)) <= {sf_sec} ORDER BY abs(extract(epoch FROM f.ts-s.ts)) LIMIT 1
  ) f ON true
  WHERE s.v <= 97
),
bili AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('bilirubin')}) {filt}),
creat AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v, unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('creatinine')}) {filt}),
plt AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('platelets')}) {filt}),
mapv AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('map')}) {filt}),
gcs AS (
  SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts,
         COALESCE(MAX(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_total')}) THEN value_as_number END),
                  SUM(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_eye')}) OR measurement_concept_id IN ({sql_concept_set('gcs_verbal')}) OR measurement_concept_id IN ({sql_concept_set('gcs_motor')}) THEN value_as_number END)
         ) AS gcs
  FROM {CLINICAL_SCHEMA}.measurement
  WHERE measurement_concept_id IN ({sql_concept_set('gcs_total')}) OR measurement_concept_id IN ({sql_concept_set('gcs_eye')}) OR measurement_concept_id IN ({sql_concept_set('gcs_verbal')}) OR measurement_concept_id IN ({sql_concept_set('gcs_motor')})
  {filt} GROUP BY 1,2,3
),
vaso AS ({sql_vasopressors(person_ids)}),
vent AS ({sql_ventilation(person_ids)}),
rrt AS ({sql_rrt(person_ids)}),
uo AS (SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('urine')}) {filt})
SELECT g.person_id, g.visit_occurrence_id, g.ts,
  (SELECT v FROM bili b WHERE b.person_id=g.person_id AND b.visit_occurrence_id=g.visit_occurrence_id AND b.ts <= g.ts AND b.ts > g.ts - interval '24 hours' ORDER BY b.ts DESC LIMIT 1) AS bili_v,
  (SELECT u FROM bili b WHERE b.person_id=g.person_id AND b.visit_occurrence_id=g.visit_occurrence_id AND b.ts <= g.ts AND b.ts > g.ts - interval '24 hours' ORDER BY b.ts DESC LIMIT 1) AS bili_u,
  (SELECT v FROM creat c WHERE c.person_id=g.person_id AND c.visit_occurrence_id=g.visit_occurrence_id AND c.ts <= g.ts AND c.ts > g.ts - interval '24 hours' ORDER BY c.ts DESC LIMIT 1) AS creat_v,
  (SELECT u FROM creat c WHERE c.person_id=g.person_id AND c.visit_occurrence_id=g.visit_occurrence_id AND c.ts <= g.ts AND c.ts > g.ts - interval '24 hours' ORDER BY c.ts DESC LIMIT 1) AS creat_u,
  (SELECT v FROM plt p WHERE p.person_id=g.person_id AND p.visit_occurrence_id=g.visit_occurrence_id AND p.ts <= g.ts AND p.ts > g.ts - interval '24 hours' ORDER BY p.ts DESC LIMIT 1) AS plt_v,
  (SELECT v FROM mapv m WHERE m.person_id=g.person_id AND m.visit_occurrence_id=g.visit_occurrence_id AND m.ts <= g.ts AND m.ts > g.ts - interval '2 hours' ORDER BY m.ts DESC LIMIT 1) AS map_v,
  (SELECT gcs FROM gcs WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts <= g.ts AND ts > g.ts - interval '4 hours' ORDER BY ts DESC LIMIT 1) AS gcs_v,
  (SELECT pao2 FROM pf_pair p WHERE p.person_id=g.person_id AND p.visit_occurrence_id=g.visit_occurrence_id AND p.ts <= g.ts AND p.ts > g.ts - interval '4 hours' ORDER BY p.ts DESC LIMIT 1) AS pao2_v,
  (SELECT pao2_u FROM pf_pair p WHERE p.person_id=g.person_id AND p.visit_occurrence_id=g.visit_occurrence_id AND p.ts <= g.ts AND p.ts > g.ts - interval '4 hours' ORDER BY p.ts DESC LIMIT 1) AS pao2_u,
  (SELECT fio2 FROM pf_pair p WHERE p.person_id=g.person_id AND p.visit_occurrence_id=g.visit_occurrence_id AND p.ts <= g.ts AND p.ts > g.ts - interval '4 hours' ORDER BY p.ts DESC LIMIT 1) AS fio2_v,
  (SELECT fio2_u FROM pf_pair p WHERE p.person_id=g.person_id AND p.visit_occurrence_id=g.visit_occurrence_id AND p.ts <= g.ts AND p.ts > g.ts - interval '4 hours' ORDER BY p.ts DESC LIMIT 1) AS fio2_u,
  (SELECT spo2 FROM sf_pair s WHERE s.person_id=g.person_id AND s.visit_occurrence_id=g.visit_occurrence_id AND s.ts <= g.ts AND s.ts > g.ts - interval '4 hours' ORDER BY s.ts DESC LIMIT 1) AS spo2_v,
  (SELECT spo2_u FROM sf_pair s WHERE s.person_id=g.person_id AND s.visit_occurrence_id=g.visit_occurrence_id AND s.ts <= g.ts AND s.ts > g.ts - interval '4 hours' ORDER BY s.ts DESC LIMIT 1) AS spo2_u,
  (SELECT fio2 FROM sf_pair s WHERE s.person_id=g.person_id AND s.visit_occurrence_id=g.visit_occurrence_id AND s.ts <= g.ts AND s.ts > g.ts - interval '4 hours' ORDER BY s.ts DESC LIMIT 1) AS sfio2_v,
  (SELECT fio2_u FROM sf_pair s WHERE s.person_id=g.person_id AND s.visit_occurrence_id=g.visit_occurrence_id AND s.ts <= g.ts AND s.ts > g.ts - interval '4 hours' ORDER BY s.ts DESC LIMIT 1) AS sfio2_u,
  EXISTS(SELECT 1 FROM vent v WHERE v.person_id=g.person_id AND v.visit_occurrence_id=g.visit_occurrence_id AND g.ts BETWEEN v.start_time AND v.end_time) AS vent,
  EXISTS(SELECT 1 FROM rrt r WHERE r.person_id=g.person_id AND r.visit_occurrence_id=g.visit_occurrence_id AND abs(extract(epoch FROM r.start_time - g.ts)) <= 43200) AS rrt,
  (SELECT SUM(v) FROM uo u WHERE u.person_id=g.person_id AND u.visit_occurrence_id=g.visit_occurrence_id AND u.ts > g.ts - interval '24 hours' AND u.ts <= g.ts) AS uo24,
  (SELECT SUM(rate_mcgkgmin * norepi_factor) FROM vaso vs WHERE vs.person_id=g.person_id AND vs.visit_occurrence_id=g.visit_occurrence_id AND g.ts BETWEEN vs.start_time AND vs.end_time) AS norepi_eq
FROM grid g
"""
    df = fetch_sql(db_conn, sql)
    df['bili'] = df.apply(lambda r: convert(r.bili_v, 'bilirubin', r.bili_u), axis=1)
    df['creat'] = df.apply(lambda r: convert(r.creat_v, 'creatinine', r.creat_u), axis=1)
    df['pao2'] = df.apply(lambda r: convert(r.pao2_v, 'pao2', r.pao2_u), axis=1)
    df['fio2'] = df.apply(lambda r: convert(r.fio2_v, 'fio2', r.fio2_u), axis=1)
    df['spo2'] = df.apply(lambda r: convert(r.spo2_v, 'spo2', r.spo2_u), axis=1)
    df['sfio2'] = df.apply(lambda r: convert(r.sfio2_v, 'fio2', r.sfio2_u), axis=1)
    df['pf'] = df['pao2'] / df['fio2'].replace(0, np.nan)
    df['sf'] = np.where(df['spo2']<=0.97, df['spo2']/df['sfio2'].replace(0, np.nan), np.nan)
    df['sf_equiv'] = (df['sf']*100 - 64) / 0.84
    df['resp'] = df.apply(lambda r: _resp_score(r.pf, r.sf_equiv, r.vent), axis=1)
    df['cardio'] = df.apply(lambda r: _cardio(r.map_v, r.norepi_eq), axis=1)
    df['neuro'] = df['gcs_v'].apply(_neuro)
    df['hepatic'] = df['bili'].apply(_hepatic)
    df['renal'] = df.apply(lambda r: _renal(r.creat, r.uo24, r.rrt), axis=1)
    df['coag'] = df['plt_v'].apply(_coag)
    df['total'] = df[['resp','cardio','neuro','hepatic','renal','coag']].sum(axis=1, min_count=4)
    return df[['person_id','visit_occurrence_id','ts','total','resp','cardio','neuro','hepatic','renal','coag','pf','sf_equiv']].rename(columns={'ts':'charttime'})

def compute_daily_sofa(db_conn, person_ids=None):
    hourly = compute_hourly_sofa(db_conn, person_ids)
    if hourly.empty: return hourly
    hourly['chartdate'] = pd.to_datetime(hourly.charttime).dt.date
    return hourly.groupby(['person_id','visit_occurrence_id','chartdate'], as_index=False).agg(
        total_sofa=('total','max'),
        resp_sofa=('resp','max'),
        cardio_sofa=('cardio','max'),
        neuro_sofa=('neuro','max'),
        hepatic_sofa=('hepatic','max'),
        renal_sofa=('renal','max'),
        coag_sofa=('coag','max')
    )
