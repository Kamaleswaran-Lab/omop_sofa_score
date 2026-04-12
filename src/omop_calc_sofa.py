"""
omop_calc_sofa.py - MGH SQL backend, full functionality preserved
Implements hourly SOFA grid, LOCF windows, unit conversions, PaO2/FiO2 pairing,
ventilation requirement, vasopressor norepi equivalents, MAP derivation, RRT override.
"""

import pandas as pd
import numpy as np
from omop_utils import (
    fetch_sql, sql_measurements, sql_vasopressors, sql_ventilation, sql_rrt, sql_urine_output,
    BILIRUBIN_IDS, CREATININE_IDS, PLATELETS_IDS, PAO2_IDS, FIO2_IDS,
    MAP_IDS, SBP_IDS, DBP_IDS, GCS_TOTAL_IDS,
    to_mg_dl_bilirubin, to_mg_dl_creatinine, to_mmhg_pao2, to_fraction_fio2, to_k_per_ul_platelets,
    _log
)

def _resp_score(pf, vent):
    if pd.isna(pf): return np.nan
    if pf >= 400: return 0
    if pf >= 300: return 1
    if pf >= 200: return 2
    if vent: return 3 if pf >= 100 else 4
    return 2 if pf >= 100 else 3

def _cardio_score(map_v, norepi):
    if not pd.isna(norepi) and norepi > 0:
        return 3 if norepi <= 0.1 else 4
    if pd.isna(map_v): return np.nan
    return 0 if map_v >= 70 else 1

def _neuro_score(gcs):
    if pd.isna(gcs): return np.nan
    if gcs >= 15: return 0
    if gcs >= 13: return 1
    if gcs >= 10: return 2
    if gcs >= 6: return 3
    return 4

def _hepatic_score(bili):
    if pd.isna(bili): return np.nan
    if bili < 1.2: return 0
    if bili < 2.0: return 1
    if bili < 6.0: return 2
    if bili < 12.0: return 3
    return 4

def _renal_score(creat, uo24, rrt):
    if rrt: return 4
    if not pd.isna(uo24):
        if uo24 < 200: return 4
        if uo24 < 500: return 3
    if pd.isna(creat): return np.nan
    if creat < 1.2: return 0
    if creat < 2.0: return 1
    if creat < 3.5: return 2
    if creat < 5.0: return 3
    return 4

def _coag_score(plt):
    if pd.isna(plt): return np.nan
    if plt >= 150: return 0
    if plt >= 100: return 1
    if plt >= 50: return 2
    if plt >= 20: return 3
    return 4

def compute_hourly_sofa(db_conn=None, cdm=None, person_ids=None):
    if db_conn is None:
        raise ValueError("db_conn required for SQL backend")
    _log("Fetching data")
    bili = fetch_sql(db_conn, sql_measurements(BILIRUBIN_IDS, person_ids))
    bili['val'] = bili.apply(lambda r: to_mg_dl_bilirubin(r.value_as_number, r.unit_name), axis=1)
    creat = fetch_sql(db_conn, sql_measurements(CREATININE_IDS, person_ids))
    creat['val'] = creat.apply(lambda r: to_mg_dl_creatinine(r.value_as_number, r.unit_name), axis=1)
    plt = fetch_sql(db_conn, sql_measurements(PLATELETS_IDS, person_ids))
    plt['val'] = plt.apply(lambda r: to_k_per_ul_platelets(r.value_as_number, r.unit_name), axis=1)
    pao2 = fetch_sql(db_conn, sql_measurements(PAO2_IDS, person_ids))
    pao2['val'] = pao2.apply(lambda r: to_mmhg_pao2(r.value_as_number, r.unit_name), axis=1)
    fio2 = fetch_sql(db_conn, sql_measurements(FIO2_IDS, person_ids))
    fio2['val'] = fio2.apply(lambda r: to_fraction_fio2(r.value_as_number, r.unit_name), axis=1)
    map_df = fetch_sql(db_conn, sql_measurements(MAP_IDS, person_ids))
    sbp = fetch_sql(db_conn, sql_measurements(SBP_IDS, person_ids))
    dbp = fetch_sql(db_conn, sql_measurements(DBP_IDS, person_ids))
    gcs = fetch_sql(db_conn, sql_measurements(GCS_TOTAL_IDS, person_ids))
    vaso = fetch_sql(db_conn, sql_vasopressors(person_ids))
    vent = fetch_sql(db_conn, sql_ventilation(person_ids))
    rrt = fetch_sql(db_conn, sql_rrt(person_ids))
    uo = fetch_sql(db_conn, sql_urine_output(person_ids))

    # derive MAP if needed
    if map_df.empty and not sbp.empty and not dbp.empty:
        s = sbp[['person_id','visit_occurrence_id','meas_time','value_as_number']].rename(columns={'value_as_number':'sbp'})
        d = dbp[['person_id','visit_occurrence_id','meas_time','value_as_number']].rename(columns={'value_as_number':'dbp'})
        m = pd.merge_asof(s.sort_values('meas_time'), d.sort_values('meas_time'),
                          on='meas_time', by=['person_id','visit_occurrence_id'],
                          direction='nearest', tolerance=pd.Timedelta('5min'))
        m['value_as_number'] = (m.sbp + 2*m.dbp)/3
        map_df = m

    # visits
    all_vis = pd.concat([
        bili[['person_id','visit_occurrence_id']],
        creat[['person_id','visit_occurrence_id']],
        plt[['person_id','visit_occurrence_id']],
        pao2[['person_id','visit_occurrence_id']],
        map_df[['person_id','visit_occurrence_id']]
    ]).drop_duplicates()

    results = []
    for _, v in all_vis.iterrows():
        pid, vid = int(v.person_id), int(v.visit_occurrence_id)
        # collect times
        tlist = []
        for df in [bili, creat, plt, pao2, fio2, map_df, gcs]:
            sub = df[(df.person_id==pid)&(df.visit_occurrence_id==vid)]
            if not sub.empty: tlist.extend(sub.meas_time.dropna().tolist())
        if not tlist: continue
        t0 = min(tlist).floor('h'); t1 = max(tlist).ceil('h')
        grid = pd.DataFrame({'ts': pd.date_range(t0, t1, freq='h')})
        grid['person_id']=pid; grid['visit_occurrence_id']=vid

        def locf(df, col, win):
            sub = df[(df.person_id==pid)&(df.visit_occurrence_id==vid)][['meas_time',col]].dropna().sort_values('meas_time')
            if sub.empty: return pd.Series([np.nan]*len(grid))
            m = pd.merge_asof(grid.sort_values('ts'), sub, left_on='ts', right_on='meas_time', direction='backward', tolerance=pd.Timedelta(win))
            return m[col]

        grid['bili'] = locf(bili.rename(columns={'val':'bili'}), 'bili', '24h')
        grid['creat'] = locf(creat.rename(columns={'val':'creat'}), 'creat', '24h')
        grid['plt'] = locf(plt.rename(columns={'val':'plt'}), 'plt', '24h')
        grid['pao2'] = locf(pao2.rename(columns={'val':'pao2'}), 'pao2', '4h')
        grid['fio2'] = locf(fio2.rename(columns={'val':'fio2'}), 'fio2', '4h')
        grid['map'] = locf(map_df.rename(columns={'value_as_number':'map'}), 'map', '2h')
        grid['gcs'] = locf(gcs.rename(columns={'value_as_number':'gcs'}), 'gcs', '4h')

        grid['pf'] = grid['pao2'] / grid['fio2'].replace(0, np.nan)
        grid['pf'] = grid['pf'].fillna(grid['pao2']/0.21)

        vsub = vent[(vent.person_id==pid)&(vent.visit_occurrence_id==vid)]
        grid['vent'] = grid['ts'].apply(lambda t: ((vsub.start_time <= t) & (vsub.end_time >= t)).any() if not vsub.empty else False)

        vsub2 = vaso[(vaso.person_id==pid)&(vaso.visit_occurrence_id==vid)]
        def norepi_eq(t):
            if vsub2.empty: return 0.0
            act = vsub2[(vsub2.start_time <= t) & ((vsub2.end_time.isna())|(vsub2.end_time >= t))]
            if act.empty: return 0.0
            total = 0.0
            for _, r in act.iterrows():
                name = str(r.drug_name).lower()
                q = float(r.quantity) if pd.notna(r.quantity) else 0
                if 'norepinephrine' in name or 'epinephrine' in name: total += q
                elif 'dopamine' in name: total += q/100.0
                elif 'phenylephrine' in name: total += q/10.0
                elif 'vasopressin' in name: total += q*2.5
            return total
        grid['norepi'] = grid['ts'].apply(norepi_eq)

        rsub = rrt[(rrt.person_id==pid)&(rrt.visit_occurrence_id==vid)]
        grid['rrt'] = grid['ts'].apply(lambda t: ((rsub.start_time >= t - pd.Timedelta('12h')) & (rsub.start_time <= t + pd.Timedelta('12h'))).any() if not rsub.empty else False)

        usub = uo[(uo.person_id==pid)&(uo.visit_occurrence_id==vid)]
        def uo24(t):
            if usub.empty: return np.nan
            w = usub[(usub.meas_time > t - pd.Timedelta('24h')) & (usub.meas_time <= t)]
            return w.urine_ml.sum() if not w.empty else np.nan
        grid['uo24'] = grid['ts'].apply(uo24)

        grid['resp'] = grid.apply(lambda r: _resp_score(r.pf, r.vent), axis=1)
        grid['cardio'] = grid.apply(lambda r: _cardio_score(r.map, r.norepi), axis=1)
        grid['neuro'] = grid['gcs'].apply(_neuro_score)
        grid['hepatic'] = grid['bili'].apply(_hepatic_score)
        grid['renal'] = grid.apply(lambda r: _renal_score(r.creat, r.uo24, r.rrt), axis=1)
        grid['coag'] = grid['plt'].apply(_coag_score)
        grid['total'] = grid[['resp','cardio','neuro','hepatic','renal','coag']].sum(axis=1, min_count=4)
        results.append(grid[['person_id','visit_occurrence_id','ts','total','resp','cardio','neuro','hepatic','renal','coag']])

    if not results: return pd.DataFrame()
    hourly = pd.concat(results, ignore_index=True).rename(columns={'ts':'charttime'})
    return hourly

def compute_daily_sofa(db_conn=None, cdm=None, person_ids=None):
    hourly = compute_hourly_sofa(db_conn=db_conn, cdm=cdm, person_ids=person_ids)
    if hourly.empty: return hourly
    hourly['chartdate'] = hourly.charttime.dt.date
    daily = hourly.groupby(['person_id','visit_occurrence_id','chartdate'], as_index=False).agg(
        total_sofa=('total','max'),
        resp_sofa=('resp','max'),
        cardio_sofa=('cardio','max'),
        neuro_sofa=('neuro','max'),
        hepatic_sofa=('hepatic','max'),
        renal_sofa=('renal','max'),
        coag_sofa=('coag','max')
    )
    return daily
