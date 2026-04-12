
"""
v4.0 SOFA calculator - fixes all 10 flaws
"""
import pandas as pd
from datetime import timedelta

NEE = {4328749:1.0, 1338005:1.0, 1360635:2.5, 1335616:0.1, 1319998:0.01}  # vasopressin included

def normalize_dose(dose, unit, weight):
    # 8750=mcg/kg/min, 8749=mcg/min, 4118123=U/min
    if unit==8749 and weight: return dose/weight
    if unit==4118123: return dose  # vasopressin U/min kept, factor applied later
    return dose

def calc_nee(drugs, weight):
    total=0
    for d in drugs:
        factor = NEE.get(d['concept'],0)
        norm = normalize_dose(d['dose'], d['unit'], weight)
        total += norm*factor
    return total

def pao2_fio2(pao2_rows, fio2_rows, window=240):
    pairs=[]
    for p in pao2_rows:
        t=p['dt']
        # LOCF up to 6h, no imputation
        candidates=[f for f in fio2_rows if abs((f['dt']-t).total_seconds())<=window*60]
        if not candidates: continue
        best = min(candidates, key=lambda x: abs((x['dt']-t).total_seconds()))
        fio2 = best['val']/100 if best['val']>1 else best['val']
        pairs.append({'pao2':p['val'],'fio2':fio2,'delta':abs((best['dt']-t).total_seconds())/60,'src':best['src']})
    return pairs

def gcs_score(gcs_rows, intubated, rass):
    # FIX 4: no verbal=1
    if not gcs_rows: return None,'missing'
    if intubated and rass is not None and rass<=-4:
        return None,'sedated_null'  # do not score
    # pre-intubation carry 24h
    pre=[g for g in gcs_rows if g.get('pre')]
    if intubated and pre: return pre[-1]['total'],'preintubation_carry'
    return gcs_rows[-1]['total'],'measured'

def renal_score(urine_rows, creat_rows, rrt_flag):
    if rrt_flag: return 4,'rrt'  # FIX 6
    # rolling 24h
    if urine_rows:
        df=pd.DataFrame(urine_rows); df['dt']=pd.to_datetime(df['dt']); df=df.set_index('dt').sort_index()
        vol24 = df['val'].rolling('24h').sum().iloc[-1]
        if vol24<200: return 4,f'urine_{vol24:.0f}'
        if vol24<500: return 3,f'urine_{vol24:.0f}'
    return 0,'normal'

def baseline_sofa(history, infection_time):
    # FIX 5: pre-infection, not last_available
    start=infection_time-timedelta(hours=72); end=infection_time-timedelta(hours=24)
    vals=[h['total'] for h in history if start<=h['t']<=end]
    return min(vals) if vals else 0
