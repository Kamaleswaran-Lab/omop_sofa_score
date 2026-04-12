"""
omop_calc_sepsis3.py - MGH SQL backend, full Sepsis-3 logic preserved
"""

import pandas as pd
from omop_utils import fetch_sql, sql_iv_antibiotics, sql_cultures, _log

def compute_suspected_infection(db_conn=None, cdm=None, ancestor_df=None, person_ids=None):
    if db_conn is None:
        raise ValueError("db_conn required")
    _log("Suspected infection")
    abx = fetch_sql(db_conn, sql_iv_antibiotics(person_ids))
    cult = fetch_sql(db_conn, sql_cultures(person_ids))
    if abx.empty or cult.empty:
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','t_inf','culture_time','abx_time'])
    out = []
    for _, c in cult.iterrows():
        pid, vid, ct = c.person_id, c.visit_occurrence_id, c.culture_time
        cand = abx[(abx.person_id==pid)&(abx.visit_occurrence_id==vid)&
                  (abx.start_time >= ct - pd.Timedelta('24h'))&
                  (abx.start_time <= ct + pd.Timedelta('72h'))].sort_values('start_time')
        if cand.empty: continue
        first = cand.iloc[0]
        dur = (cand.start_time.max() - first.start_time).total_seconds()/3600.0
        if len(cand) >= 2 or dur >= 24:
            t_inf = min(ct, first.start_time)
            out.append({'person_id':pid,'visit_occurrence_id':vid,'t_inf':t_inf,
                        'culture_time':ct,'abx_time':first.start_time})
    return pd.DataFrame(out).drop_duplicates(['person_id','visit_occurrence_id','t_inf'])

def evaluate_sepsis3(hourly_sofa, suspected, db_conn=None, cdm=None, ancestor_df=None):
    if suspected.empty or hourly_sofa.empty:
        return pd.DataFrame()
    res = []
    for _, inf in suspected.iterrows():
        pid, vid, t0 = inf.person_id, inf.visit_occurrence_id, inf.t_inf
        sofa = hourly_sofa[(hourly_sofa.person_id==pid)&(hourly_sofa.visit_occurrence_id==vid)]
        if sofa.empty: continue
        base_win = sofa[(sofa.charttime >= t0 - pd.Timedelta('72h')) & (sofa.charttime <= t0 - pd.Timedelta('1h'))]
        if base_win.empty: continue
        baseline = base_win.sort_values('charttime').iloc[-1].total
        acute_win = sofa[(sofa.charttime >= t0 - pd.Timedelta('48h')) & (sofa.charttime <= t0 + pd.Timedelta('24h'))]
        if acute_win.empty: continue
        acute = acute_win.total.max()
        delta = acute - baseline
        res.append({'person_id':pid,'visit_occurrence_id':vid,'t_inf':t0,
                    'baseline_sofa':baseline,'max_sofa':acute,'delta_sofa':delta,
                    'sepsis3': int(delta >= 2)})
    return pd.DataFrame(res)
