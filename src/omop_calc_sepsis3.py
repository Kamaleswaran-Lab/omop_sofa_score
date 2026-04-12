"""
omop_calc_sepsis3.py v3.2 - Pragmatic baseline
"""

import pandas as pd
from omop_utils import fetch, sql_abx, sql_cultures
from config_pragmatic import BASELINE_STRATEGY

def compute_suspected_infection(conn, person_ids=None):
    abx=fetch(conn,sql_abx(person_ids)); cult=fetch(conn,sql_cultures(person_ids))
    if abx.empty or cult.empty: return pd.DataFrame()
    out=[]
    for _,c in cult.iterrows():
        cand=abx[(abx.person_id==c.person_id)&(abx.visit_occurrence_id==c.visit_occurrence_id)&(abx.t>=c.t-pd.Timedelta('24h'))&(abx.t<=c.t+pd.Timedelta('72h'))].sort_values('t')
        if cand.empty: continue
        f=cand.iloc[0]
        if len(cand)>=2 or (cand.t.max()-f.t).total_seconds()>=86400:
            out.append({'person_id':c.person_id,'visit_occurrence_id':c.visit_occurrence_id,'t_inf':min(c.t,f.t),'culture_time':c.t,'abx_time':f.t})
    return pd.DataFrame(out).drop_duplicates(['person_id','visit_occurrence_id','t_inf'])

def evaluate_sepsis3(hourly, suspected):
    res=[]
    for _,inf in suspected.iterrows():
        s=hourly[(hourly.person_id==inf.person_id)&(hourly.visit_occurrence_id==inf.visit_occurrence_id)]
        if s.empty: continue
        if BASELINE_STRATEGY=="min_72_6":
            b=s[(s.charttime>=inf.t_inf-pd.Timedelta(hours=72))&(s.charttime<=inf.t_inf-pd.Timedelta(hours=6))]
            baseline=b.total.min() if not b.empty else 0; src='min_72_6'
        elif BASELINE_STRATEGY=="last_available":
            b=s[(s.charttime>=inf.t_inf-pd.Timedelta(hours=72))&(s.charttime<=inf.t_inf-pd.Timedelta(hours=6))]
            if not b.empty: baseline=b.total.min(); src='min_72_6'
            else:
                b2=s[(s.charttime>=inf.t_inf-pd.Timedelta(hours=24))&(s.charttime<=inf.t_inf-pd.Timedelta(hours=1))]
                if not b2.empty: baseline=b2.total.iloc[-1]; src='last_24_1'
                else: baseline=0; src='imputed_zero'
        else: baseline=0; src='zero'
        acute=s[(s.charttime>=inf.t_inf-pd.Timedelta(hours=48))&(s.charttime<=inf.t_inf+pd.Timedelta(hours=24))].total.max()
        if pd.isna(acute): continue
        res.append({'person_id':inf.person_id,'visit_occurrence_id':inf.visit_occurrence_id,'t_inf':inf.t_inf,'baseline_sofa':baseline,'baseline_source':src,'max_sofa':acute,'delta_sofa':acute-baseline,'sepsis3':int(acute-baseline>=2)})
    return pd.DataFrame(res)
