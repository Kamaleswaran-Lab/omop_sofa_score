"""
omop_calc_sofa.py v3.2 - Pragmatic
"""

import pandas as pd, numpy as np
from omop_utils import *
from config_pragmatic import *

def compute_hourly_sofa(conn, person_ids=None):
    pf_sec = PAO2_FIO2_WINDOW*60
    sf_sec = SPO2_FIO2_WINDOW*60
    filt = f"AND person_id IN ({','.join(map(str,person_ids))})" if person_ids else ""
    
    sql = f"""
WITH grid AS (
 SELECT person_id,visit_occurrence_id,generate_series(date_trunc('hour',MIN(ts)),date_trunc('hour',MAX(ts)),interval '1 hour') AS ts
 FROM (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('pao2')}) UNION ALL SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('creatinine')})) u WHERE 1=1 {filt} GROUP BY 1,2
),
pao2 AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v,unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('pao2')}) {filt}),
fio2 AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v,unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('fio2')}) {filt}),
spo2 AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v,unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('spo2')}) {filt}),
pf AS (SELECT p.person_id,p.visit_occurrence_id,p.ts,p.v AS pao2,p.u AS pu,f.v AS fio2,f.u AS fu FROM pao2 p LEFT JOIN LATERAL (SELECT v,u FROM fio2 f WHERE f.person_id=p.person_id AND f.visit_occurrence_id=p.visit_occurrence_id AND abs(extract(epoch FROM f.ts-p.ts))<={pf_sec} ORDER BY abs(extract(epoch FROM f.ts-p.ts)) LIMIT 1) f ON true),
sf AS (SELECT s.person_id,s.visit_occurrence_id,s.ts,s.v AS spo2,s.u AS su,f.v AS fio2,f.u AS fu FROM spo2 s LEFT JOIN LATERAL (SELECT v,u FROM fio2 f WHERE f.person_id=s.person_id AND f.visit_occurrence_id=s.visit_occurrence_id AND abs(extract(epoch FROM f.ts-s.ts))<={sf_sec} ORDER BY abs(extract(epoch FROM f.ts-s.ts)) LIMIT 1) f ON true WHERE s.v<=97),
vent AS ({sql_ventilation(person_ids)}),
bili AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v,unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('bilirubin')}) {filt}),
creat AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v,unit_concept_id AS u FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('creatinine')}) {filt}),
plt AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('platelets')}) {filt}),
mapv AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('map')}) {filt}),
gcs AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,COALESCE(MAX(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_total')}) THEN value_as_number END),SUM(CASE WHEN measurement_concept_id IN ({sql_concept_set('gcs_eye')}) OR measurement_concept_id IN ({sql_concept_set('gcs_verbal')}) OR measurement_concept_id IN ({sql_concept_set('gcs_motor')}) THEN value_as_number END)) AS gcs FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('gcs_total')}) OR measurement_concept_id IN ({sql_concept_set('gcs_eye')}) OR measurement_concept_id IN ({sql_concept_set('gcs_verbal')}) OR measurement_concept_id IN ({sql_concept_set('gcs_motor')}) {filt} GROUP BY 1,2,3),
vaso AS ({sql_vasopressors(person_ids)}),
rrt AS (SELECT person_id,visit_occurrence_id,COALESCE(procedure_datetime,procedure_date) AS t FROM {CLINICAL_SCHEMA}.procedure_occurrence WHERE procedure_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id=4146536) {filt}),
uo AS (SELECT person_id,visit_occurrence_id,COALESCE(measurement_datetime,measurement_date) AS ts,value_as_number AS v FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('urine')}) {filt})
SELECT g.person_id,g.visit_occurrence_id,g.ts,
 (SELECT v FROM bili b WHERE b.person_id=g.person_id AND b.visit_occurrence_id=g.visit_occurrence_id AND b.ts<=g.ts AND b.ts>g.ts-interval '24 hours' ORDER BY b.ts DESC LIMIT 1) AS bv,
 (SELECT u FROM bili b WHERE b.person_id=g.person_id AND b.visit_occurrence_id=g.visit_occurrence_id AND b.ts<=g.ts AND b.ts>g.ts-interval '24 hours' ORDER BY b.ts DESC LIMIT 1) AS bu,
 (SELECT v FROM creat c WHERE c.person_id=g.person_id AND c.visit_occurrence_id=g.visit_occurrence_id AND c.ts<=g.ts AND c.ts>g.ts-interval '24 hours' ORDER BY c.ts DESC LIMIT 1) AS cv,
 (SELECT u FROM creat c WHERE c.person_id=g.person_id AND c.visit_occurrence_id=g.visit_occurrence_id AND c.ts<=g.ts AND c.ts>g.ts-interval '24 hours' ORDER BY c.ts DESC LIMIT 1) AS cu,
 (SELECT v FROM plt p WHERE p.person_id=g.person_id AND p.visit_occurrence_id=g.visit_occurrence_id AND p.ts<=g.ts AND p.ts>g.ts-interval '24 hours' ORDER BY p.ts DESC LIMIT 1) AS pv,
 (SELECT v FROM mapv m WHERE m.person_id=g.person_id AND m.visit_occurrence_id=g.visit_occurrence_id AND m.ts<=g.ts AND m.ts>g.ts-interval '2 hours' ORDER BY m.ts DESC LIMIT 1) AS mv,
 (SELECT gcs FROM gcs WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS gv,
 (SELECT pao2 FROM pf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS pao2v,
 (SELECT pu FROM pf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS pao2u,
 (SELECT fio2 FROM pf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS fio2v,
 (SELECT fu FROM pf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS fio2u,
 (SELECT spo2 FROM sf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS spo2v,
 (SELECT su FROM sf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS spo2u,
 (SELECT fio2 FROM sf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS sfio2v,
 (SELECT fu FROM sf WHERE person_id=g.person_id AND visit_occurrence_id=g.visit_occurrence_id AND ts<=g.ts AND ts>g.ts-interval '4 hours' ORDER BY ts DESC LIMIT 1) AS sfio2u,
 EXISTS(SELECT 1 FROM vent v WHERE v.person_id=g.person_id AND v.visit_occurrence_id=g.visit_occurrence_id AND g.ts BETWEEN v.s AND v.e) AS vent,
 EXISTS(SELECT 1 FROM rrt r WHERE r.person_id=g.person_id AND r.visit_occurrence_id=g.visit_occurrence_id AND abs(extract(epoch FROM r.t-g.ts))<=43200) AS rrt,
 (SELECT SUM(v) FROM uo u WHERE u.person_id=g.person_id AND u.visit_occurrence_id=g.visit_occurrence_id AND u.ts>g.ts-interval '24 hours' AND u.ts<=g.ts) AS uo24,
 (SELECT SUM(rate*norepi_factor) FROM vaso vs WHERE vs.person_id=g.person_id AND vs.visit_occurrence_id=g.visit_occurrence_id AND g.ts BETWEEN vs.start_time AND vs.end_time) AS ne,
 (SELECT rate_source FROM vaso vs WHERE vs.person_id=g.person_id AND vs.visit_occurrence_id=g.visit_occurrence_id AND g.ts BETWEEN vs.start_time AND vs.end_time ORDER BY vs.start_time DESC LIMIT 1) AS ne_src
FROM grid g
"""
    df = fetch(conn, sql)
    df['bili']=df.apply(lambda r: convert(r.bv,'bilirubin',r.bu),axis=1)
    df['creat']=df.apply(lambda r: convert(r.cv,'creatinine',r.cu),axis=1)
    df['pao2']=df.apply(lambda r: convert(r.pao2v,'pao2',r.pao2u),axis=1)
    df['fio2']=df.apply(lambda r: convert(r.fio2v,'fio2',r.fio2u),axis=1)
    df['spo2']=df.apply(lambda r: convert(r.spo2v,'spo2',r.spo2u),axis=1)
    df['sfio2']=df.apply(lambda r: convert(r.sfio2v,'fio2',r.sfio2u),axis=1)
    df['pf']=df['pao2']/df['fio2'].replace(0,np.nan)
    df['sf']=np.where(df['spo2']<=0.97, df['spo2']/df['sfio2'].replace(0,np.nan), np.nan)
    # Conditional FiO2 imputation
    if FIO2_IMPUTATION == "conditional":
        df['fio2_imp']=df['fio2']
        mask = df['fio2'].isna() & df['vent']
        df.loc[mask,'fio2_imp']=0.6
        df.loc[mask,'fio2_imp_src']='vent_assumed_60'
        mask2 = df['fio2'].isna() & ~df['vent'] & df['spo2'].isna()
        df.loc[mask2,'fio2_imp']=0.21
        df.loc[mask2,'fio2_imp_src']='room_air'
        df['pf']=df['pao2']/df['fio2_imp'].replace(0,np.nan)
    df['sf_eq']=(df['sf']*100-64)/0.84
    df['resp']=df.apply(lambda r: 0 if (r.pf if pd.notna(r.pf) else r.sf_eq)>=400 else 1 if (r.pf if pd.notna(r.pf) else r.sf_eq)>=300 else 2 if (r.pf if pd.notna(r.pf) else r.sf_eq)>=200 else (3 if (r.pf if pd.notna(r.pf) else r.sf_eq)>=100 else 4) if r.vent else (2 if (r.pf if pd.notna(r.pf) else r.sf_eq)>=100 else 3) if pd.notna(r.pf if pd.notna(r.pf) else r.sf_eq) else np.nan, axis=1)
    df['cardio']=df.apply(lambda r: 3 if pd.notna(r.ne) and r.ne<=0.1 else 4 if pd.notna(r.ne) and r.ne>0.1 else (0 if r.mv>=70 else 1) if pd.notna(r.mv) else np.nan, axis=1)
    df['neuro']=df['gv'].apply(lambda x: 0 if x>=15 else 1 if x>=13 else 2 if x>=10 else 3 if x>=6 else 4 if pd.notna(x) else np.nan)
    df['hepatic']=df['bili'].apply(lambda x: 0 if x<1.2 else 1 if x<2 else 2 if x<6 else 3 if x<12 else 4 if pd.notna(x) else np.nan)
    df['renal']=df.apply(lambda r: 4 if r.rrt else (4 if r.uo24<200 else 3 if r.uo24<500 else np.nan) if pd.notna(r.uo24) else (0 if r.creat<1.2 else 1 if r.creat<2 else 2 if r.creat<3.5 else 3 if r.creat<5 else 4) if pd.notna(r.creat) else np.nan, axis=1)
    df['coag']=df['pv'].apply(lambda x: 0 if x>=150 else 1 if x>=100 else 2 if x>=50 else 3 if x>=20 else 4 if pd.notna(x) else np.nan)
    df['total']=df[['resp','cardio','neuro','hepatic','renal','coag']].sum(axis=1,min_count=4)
    return df[['person_id','visit_occurrence_id','ts','total','resp','cardio','neuro','hepatic','renal','coag','pf','sf_eq','ne','ne_src']].rename(columns={'ts':'charttime'})

def compute_daily_sofa(conn, person_ids=None):
    h=compute_hourly_sofa(conn,person_ids)
    if h.empty: return h
    h['chartdate']=pd.to_datetime(h.charttime).dt.date
    return h.groupby(['person_id','visit_occurrence_id','chartdate'],as_index=False).agg(total_sofa=('total','max'),resp_sofa=('resp','max'),cardio_sofa=('cardio','max'),neuro_sofa=('neuro','max'),hepatic_sofa=('hepatic','max'),renal_sofa=('renal','max'),coag_sofa=('coag','max'))
