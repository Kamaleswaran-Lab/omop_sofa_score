"""
omop_calc_sepsis3.py - Sepsis-3 with corrected baseline
"""

import pandas as pd
from omop_utils import fetch_sql, sql_iv_antibiotics, sql_cultures

def compute_suspected_infection(db_conn, person_ids=None):
    abx = fetch_sql(db_conn, sql_iv_antibiotics(person_ids))
    cult = fetch_sql(db_conn, sql_cultures(person_ids))
    if abx.empty or cult.empty: return pd.DataFrame()
    out=[]
    for _,c in cult.iterrows():
        cand = abx[(abx.person_id==c.person_id)&(abx.visit_occurrence_id==c.visit_occurrence_id)&
                   (abx.start_time>=c.culture_time-pd.Timedelta('24h'))&
                   (abx.start_time<=c.culture_time+pd.Timedelta('72h'))].sort_values('start_time')
        if cand.empty: continue
        first=cand.iloc[0]
        if len(cand)>=2 or (cand.start_time.max()-first.start_time).total_seconds()>=86400:
            out.append({'person_id':c.person_id,'visit_occurrence_id':c.visit_occurrence_id,
                        't_inf':min(c.culture_time, first.start_time),
                        'culture_time':c.culture_time,'abx_time':first.start_time})
    return pd.DataFrame(out).drop_duplicates(['person_id','visit_occurrence_id','t_inf'])

def evaluate_sepsis3(hourly_sofa, suspected):
    res=[]
    for _,inf in suspected.iterrows():
        sofa = hourly_sofa[(hourly_sofa.person_id==inf.person_id)&(hourly_sofa.visit_occurrence_id==inf.visit_occurrence_id)]
        if sofa.empty: continue
        base = sofa[(sofa.charttime>=inf.t_inf-pd.Timedelta(hours=72))&(sofa.charttime<=inf.t_inf-pd.Timedelta(hours=6))]
        baseline = base.total.min() if not base.empty else 0
        acute = sofa[(sofa.charttime>=inf.t_inf-pd.Timedelta(hours=48))&(sofa.charttime<=inf.t_inf+pd.Timedelta(hours=24))].total.max()
        if pd.isna(acute): continue
        res.append({'person_id':inf.person_id,'visit_occurrence_id':inf.visit_occurrence_id,'t_inf':inf.t_inf,
                    'baseline_sofa':baseline,'max_sofa':acute,'delta_sofa':acute-baseline,'sepsis3':int(acute-baseline>=2)})
    return pd.DataFrame(res)
