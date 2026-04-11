import pandas as pd
import numpy as np
from datetime import timedelta
from omop_utils import (
    get_measurements, derive_map, derive_gcs, get_paired_pao2_fio2,
    get_urine_output_24h, get_vasopressors, CONCEPT_SEEDS, expand_concepts, normalize_cdm, VERBOSE, vprint
)

def score_respiratory(pfratio, on_vent):
    if pd.isna(pfratio): return np.nan
    if pfratio > 400: return 0
    if pfratio > 300: return 1
    if pfratio > 200: return 2
    if pfratio > 100: return 3 if on_vent else 2
    return 4 if on_vent else 2

def score_cardiovascular(map_val, vaso_rates, on_vaso_any=False):
    norepi = vaso_rates.get('norepi', 0) or 0
    epi = vaso_rates.get('epi', 0) or 0
    dopa = vaso_rates.get('dopamine', 0) or 0
    dobu = vaso_rates.get('dobutamine', 0) or 0
    total_norepi_eq = norepi + epi
    has_rate_data = any([not pd.isna(x) and x>0 for x in [norepi, epi, dopa, dobu]])
    if not has_rate_data and on_vaso_any:
        return 3
    if total_norepi_eq == 0 and dobu == 0 and dopa == 0:
        if pd.isna(map_val) or map_val >= 70: return 0
        return 1
    if dobu > 0 and total_norepi_eq == 0 and dopa == 0: return 2
    if dopa > 0 and dopa <= 5 and total_norepi_eq == 0: return 2
    if dopa > 15 or total_norepi_eq > 0.1: return 4
    if dopa > 5 or total_norepi_eq <= 0.1: return 3
    return 2

def score_neurologic(gcs):
    if pd.isna(gcs): return np.nan
    if gcs >= 15: return 0
    if gcs >= 13: return 1
    if gcs >= 10: return 2
    if gcs >= 6: return 3
    return 4

def score_hepatic(bili):
    if pd.isna(bili): return np.nan
    if bili < 1.2: return 0
    if bili < 2.0: return 1
    if bili < 6.0: return 2
    if bili < 12.0: return 3
    return 4

def score_renal(creat, uo_24h, on_rrt):
    if on_rrt: return 4
    creat_score = np.nan
    if not pd.isna(creat):
        if creat < 1.2: creat_score = 0
        elif creat < 2.0: creat_score = 1
        elif creat < 3.5: creat_score = 2
        elif creat < 5.0: creat_score = 3
        else: creat_score = 4
    uo_score = np.nan
    if not pd.isna(uo_24h):
        if uo_24h < 200: uo_score = 4
        elif uo_24h < 500: uo_score = 3
    scores = [s for s in [creat_score, uo_score] if not pd.isna(s)]
    return max(scores) if scores else np.nan

def score_coagulation(plt):
    if pd.isna(plt): return np.nan
    if plt > 150: return 0
    if plt > 100: return 1
    if plt > 50: return 2
    if plt > 20: return 3
    return 4

def compute_daily_sofa(cdm, ancestor_df=None, min_components=1, impute_missing_as_zero=False):
    cdm = normalize_cdm(cdm)
    if ancestor_df is not None:
        ancestor_df.columns = [c.lower() for c in ancestor_df.columns]

    print("Extracting measurements...")
    map_ts = derive_map(cdm, ancestor_df)
    gcs_ts = derive_gcs(cdm, ancestor_df)
    pf_ts = get_paired_pao2_fio2(cdm, ancestor_df)
    bili_ts = get_measurements(cdm, ['bilirubin_total'], domain='bilirubin', ancestor_df=ancestor_df)
    creat_ts = get_measurements(cdm, ['creatinine'], domain='creatinine', ancestor_df=ancestor_df)
    plt_ts = get_measurements(cdm, ['platelets'], domain='platelets', ancestor_df=ancestor_df)
    uo_daily = get_urine_output_24h(cdm, ancestor_df)
    vaso = get_vasopressors(cdm, ancestor_df)

    def standardize_ts(ts, value_col):
        if ts is None or ts.empty:
            return pd.DataFrame(columns=['person_id', 'visit_occurrence_id', 'charttime', value_col])

        ts = ts.copy()
        ts.columns = [c.lower() for c in ts.columns]

        value_candidates = [
            value_col, 'value_as_number', 'value', 'measurement_value', 'numeric_value',
            'result', 'result_numeric', 'lab_value'
        ]
        source_val = next((c for c in value_candidates if c in ts.columns), None)
        if source_val is None:
            raise KeyError(f"Could not find a value column for '{value_col}'. Available columns: {list(ts.columns)}")

        time_candidates = ['charttime', 'measurement_datetime', 'measurement_time', 'datetime', 'event_time']
        source_time = next((c for c in time_candidates if c in ts.columns), None)
        if source_time is None:
            raise KeyError(f"Could not find a datetime column for '{value_col}'. Available columns: {list(ts.columns)}")

        missing = [c for c in ['person_id', 'visit_occurrence_id'] if c not in ts.columns]
        if missing:
            raise KeyError(f"Missing required ID columns for '{value_col}': {missing}")

        ts = ts[['person_id', 'visit_occurrence_id', source_time, source_val]].rename(
            columns={source_time: 'charttime', source_val: value_col}
        )
        ts['person_id'] = pd.to_numeric(ts['person_id'], errors='coerce')
        ts['visit_occurrence_id'] = pd.to_numeric(ts['visit_occurrence_id'], errors='coerce')
        ts['charttime'] = pd.to_datetime(ts['charttime'], errors='coerce')
        ts[value_col] = pd.to_numeric(ts[value_col], errors='coerce')
        ts = ts.dropna(subset=['person_id', 'visit_occurrence_id', 'charttime'])
        ts['person_id'] = ts['person_id'].astype('int64')
        ts['visit_occurrence_id'] = ts['visit_occurrence_id'].astype('int64')
        ts = ts.sort_values(['person_id', 'visit_occurrence_id', 'charttime']).reset_index(drop=True)
        return ts

    map_ts = standardize_ts(map_ts, 'map')
    gcs_ts = standardize_ts(gcs_ts, 'gcs')
    pf_ts = standardize_ts(pf_ts, 'pfratio')
    bili_ts = standardize_ts(bili_ts, 'bili')
    creat_ts = standardize_ts(creat_ts, 'creat')
    plt_ts = standardize_ts(plt_ts, 'plt')

    vent_ids = expand_concepts(ancestor_df, CONCEPT_SEEDS['mech_vent'])
    vent = cdm['procedure_occurrence'].copy()
    vent.columns = [c.lower() for c in vent.columns]
    vent = vent[vent['procedure_concept_id'].isin(vent_ids)][['person_id', 'visit_occurrence_id', 'procedure_datetime']]
    vent = vent.rename(columns={'procedure_datetime': 'charttime'})
    vent['on_vent'] = 1
    vent['person_id'] = pd.to_numeric(vent['person_id'], errors='coerce')
    vent['visit_occurrence_id'] = pd.to_numeric(vent['visit_occurrence_id'], errors='coerce')
    vent['charttime'] = pd.to_datetime(vent['charttime'], errors='coerce')
    vent = vent.dropna(subset=['person_id', 'visit_occurrence_id', 'charttime'])
    vent['person_id'] = vent['person_id'].astype('int64')
    vent['visit_occurrence_id'] = vent['visit_occurrence_id'].astype('int64')
    vent = vent.sort_values(['person_id', 'visit_occurrence_id', 'charttime']).reset_index(drop=True)

    rrt_ids = expand_concepts(ancestor_df, CONCEPT_SEEDS['rrt_procedure'])
    rrt = cdm['procedure_occurrence'].copy()
    rrt.columns = [c.lower() for c in rrt.columns]
    rrt = rrt[rrt['procedure_concept_id'].isin(rrt_ids)][['person_id', 'visit_occurrence_id', 'procedure_datetime']]
    rrt = rrt.rename(columns={'procedure_datetime': 'charttime'})
    rrt['on_rrt'] = 1
    rrt['person_id'] = pd.to_numeric(rrt['person_id'], errors='coerce')
    rrt['visit_occurrence_id'] = pd.to_numeric(rrt['visit_occurrence_id'], errors='coerce')
    rrt['charttime'] = pd.to_datetime(rrt['charttime'], errors='coerce')
    rrt = rrt.dropna(subset=['person_id', 'visit_occurrence_id', 'charttime'])
    rrt['person_id'] = rrt['person_id'].astype('int64')
    rrt['visit_occurrence_id'] = rrt['visit_occurrence_id'].astype('int64')
    rrt = rrt.sort_values(['person_id', 'visit_occurrence_id', 'charttime']).reset_index(drop=True)

    visits = cdm['visit_occurrence'][['person_id', 'visit_occurrence_id', 'visit_start_datetime', 'visit_end_datetime']].copy()
    visits.columns = [c.lower() for c in visits.columns]
    visits['visit_start_datetime'] = pd.to_datetime(visits['visit_start_datetime'], errors='coerce')
    visits['visit_end_datetime'] = pd.to_datetime(
        visits['visit_end_datetime'].fillna(visits['visit_start_datetime'] + pd.Timedelta(days=30)),
        errors='coerce'
    )
    visits['person_id'] = pd.to_numeric(visits['person_id'], errors='coerce')
    visits['visit_occurrence_id'] = pd.to_numeric(visits['visit_occurrence_id'], errors='coerce')
    visits = visits.dropna(subset=['person_id', 'visit_occurrence_id', 'visit_start_datetime', 'visit_end_datetime'])
    visits['person_id'] = visits['person_id'].astype('int64')
    visits['visit_occurrence_id'] = visits['visit_occurrence_id'].astype('int64')
    visits = visits.sort_values(['person_id', 'visit_occurrence_id', 'visit_start_datetime']).reset_index(drop=True)

    hourly_rows = []
    for _, v in visits.iterrows():
        hrs = pd.date_range(v['visit_start_datetime'].floor('h'), v['visit_end_datetime'].ceil('h'), freq='h')
        hourly_rows.append(pd.DataFrame({
            'person_id': v['person_id'],
            'visit_occurrence_id': v['visit_occurrence_id'],
            'charttime': hrs
        }))

    if not hourly_rows:
        return pd.DataFrame(columns=[
            'person_id', 'visit_occurrence_id', 'chartdate', 'total_sofa', 'components_present',
            'resp_sofa', 'cardio_sofa', 'neuro_sofa', 'hepatic_sofa', 'renal_sofa', 'coag_sofa'
        ])

    grid = pd.concat(hourly_rows, ignore_index=True)
    grid['person_id'] = pd.to_numeric(grid['person_id'], errors='coerce').astype('int64')
    grid['visit_occurrence_id'] = pd.to_numeric(grid['visit_occurrence_id'], errors='coerce').astype('int64')
    grid['charttime'] = pd.to_datetime(grid['charttime'], errors='coerce')
    grid = grid.dropna(subset=['person_id', 'visit_occurrence_id', 'charttime'])
    grid = grid.sort_values(['person_id', 'visit_occurrence_id', 'charttime']).reset_index(drop=True)

    def merge_locf(grid, ts, value_col, window='4h'):
        if ts.empty:
            grid[value_col] = np.nan
            return grid

        out_parts = []
        for (pid, vid), g_part in grid.groupby(['person_id', 'visit_occurrence_id'], sort=False):
            t_part = ts[(ts['person_id'] == pid) & (ts['visit_occurrence_id'] == vid)][
                ['charttime', value_col]
            ].sort_values('charttime')

            g_part = g_part.sort_values('charttime').copy()

            if t_part.empty:
                g_part[value_col] = np.nan
            else:
                merged = pd.merge_asof(
                    g_part,
                    t_part,
                    on='charttime',
                    direction='backward',
                    tolerance=pd.Timedelta(window)
                )
                g_part[value_col] = merged[value_col].to_numpy()

            out_parts.append(g_part)

        return pd.concat(out_parts, ignore_index=True).sort_values(
            ['person_id', 'visit_occurrence_id', 'charttime']
        ).reset_index(drop=True)

    grid = merge_locf(grid, map_ts, 'map', '2h')
    grid = merge_locf(grid, gcs_ts, 'gcs', '4h')
    grid = merge_locf(grid, pf_ts, 'pfratio', '4h')
    grid = merge_locf(grid, bili_ts, 'bili', '48h')
    grid = merge_locf(grid, creat_ts, 'creat', '48h')
    grid = merge_locf(grid, plt_ts, 'plt', '48h')
    grid = merge_locf(grid, vent[['person_id', 'visit_occurrence_id', 'charttime', 'on_vent']], 'on_vent', '24h')
    grid['on_vent'] = grid['on_vent'].fillna(0).astype(int)
    grid = merge_locf(grid, rrt[['person_id', 'visit_occurrence_id', 'charttime', 'on_rrt']], 'on_rrt', '24h')
    grid['on_rrt'] = grid['on_rrt'].fillna(0).astype(int)

    vaso_hourly = []
    if not vaso.empty:
        vaso = vaso.copy()
        vaso.columns = [c.lower() for c in vaso.columns]
        vaso['start'] = pd.to_datetime(vaso['start'], errors='coerce')
        vaso['end'] = pd.to_datetime(vaso['end'], errors='coerce')
        vaso['person_id'] = pd.to_numeric(vaso['person_id'], errors='coerce')
        vaso['visit_occurrence_id'] = pd.to_numeric(vaso['visit_occurrence_id'], errors='coerce')
        vaso['drug_concept_id'] = pd.to_numeric(vaso['drug_concept_id'], errors='coerce')
        vaso['rate_mcg_kg_min'] = pd.to_numeric(vaso['rate_mcg_kg_min'], errors='coerce')
        vaso = vaso.dropna(subset=['person_id', 'visit_occurrence_id', 'start', 'end', 'drug_concept_id'])
        vaso['person_id'] = vaso['person_id'].astype('int64')
        vaso['visit_occurrence_id'] = vaso['visit_occurrence_id'].astype('int64')
        vaso['drug_concept_id'] = vaso['drug_concept_id'].astype('int64')

        norepi_ids = set(expand_concepts(ancestor_df, CONCEPT_SEEDS['norepinephrine']))
        epi_ids = set(expand_concepts(ancestor_df, CONCEPT_SEEDS['epinephrine']))
        dopamine_ids = set(expand_concepts(ancestor_df, CONCEPT_SEEDS['dopamine']))
        dobutamine_ids = set(expand_concepts(ancestor_df, CONCEPT_SEEDS['dobutamine']))

        for _, v in visits.iterrows():
            v_vaso = vaso[vaso['visit_occurrence_id'] == v['visit_occurrence_id']]
            if v_vaso.empty:
                continue
            hrs = pd.date_range(v['visit_start_datetime'].floor('h'), v['visit_end_datetime'].ceil('h'), freq='h')
            for hr in hrs:
                active = v_vaso[(v_vaso['start'] <= hr) & (v_vaso['end'] >= hr)]
                if not active.empty:
                    vaso_hourly.append({
                        'person_id': v['person_id'],
                        'visit_occurrence_id': v['visit_occurrence_id'],
                        'charttime': hr,
                        'on_vaso_any': 1,
                        'norepi': active.loc[active['drug_concept_id'].isin(norepi_ids), 'rate_mcg_kg_min'].max(),
                        'epi': active.loc[active['drug_concept_id'].isin(epi_ids), 'rate_mcg_kg_min'].max(),
                        'dopamine': active.loc[active['drug_concept_id'].isin(dopamine_ids), 'rate_mcg_kg_min'].max(),
                        'dobutamine': active.loc[active['drug_concept_id'].isin(dobutamine_ids), 'rate_mcg_kg_min'].max(),
                    })

    vaso_df = pd.DataFrame(vaso_hourly)
    if not vaso_df.empty:
        vaso_df['person_id'] = pd.to_numeric(vaso_df['person_id'], errors='coerce').astype('int64')
        vaso_df['visit_occurrence_id'] = pd.to_numeric(vaso_df['visit_occurrence_id'], errors='coerce').astype('int64')
        vaso_df['charttime'] = pd.to_datetime(vaso_df['charttime'], errors='coerce')
        grid = grid.merge(vaso_df, on=['person_id', 'visit_occurrence_id', 'charttime'], how='left')
    else:
        for col in ['norepi', 'epi', 'dopamine', 'dobutamine', 'on_vaso_any']:
            grid[col] = np.nan

    grid['resp_sofa'] = grid.apply(lambda r: score_respiratory(r['pfratio'], r['on_vent']), axis=1)
    grid['cardio_sofa'] = grid.apply(
        lambda r: score_cardiovascular(
            r['map'],
            {
                'norepi': r.get('norepi', 0),
                'epi': r.get('epi', 0),
                'dopamine': r.get('dopamine', 0),
                'dobutamine': r.get('dobutamine', 0)
            },
            on_vaso_any=bool(r.get('on_vaso_any', 0))
        ),
        axis=1
    )
    grid['neuro_sofa'] = grid['gcs'].apply(score_neurologic)
    grid['hepatic_sofa'] = grid['bili'].apply(score_hepatic)
    grid['coag_sofa'] = grid['plt'].apply(score_coagulation)

    grid['chartdate'] = grid['charttime'].dt.floor('D')
    uo_daily = uo_daily.copy()
    uo_daily.columns = [c.lower() for c in uo_daily.columns]
    uo_daily['person_id'] = pd.to_numeric(uo_daily['person_id'], errors='coerce')
    uo_daily['visit_occurrence_id'] = pd.to_numeric(uo_daily['visit_occurrence_id'], errors='coerce')
    uo_daily['chartdate'] = pd.to_datetime(uo_daily['chartdate'], errors='coerce').dt.floor('D')
    uo_daily = uo_daily.dropna(subset=['person_id', 'visit_occurrence_id', 'chartdate'])
    uo_daily['person_id'] = uo_daily['person_id'].astype('int64')
    uo_daily['visit_occurrence_id'] = uo_daily['visit_occurrence_id'].astype('int64')

    grid = grid.merge(uo_daily, on=['person_id', 'visit_occurrence_id', 'chartdate'], how='left')
    grid['renal_sofa'] = grid.apply(
        lambda r: score_renal(r['creat'], r.get('uo_24h_ml', np.nan), r['on_rrt']),
        axis=1
    )

    daily = grid.groupby(['person_id', 'visit_occurrence_id', 'chartdate']).agg({
        'resp_sofa': 'max',
        'cardio_sofa': 'max',
        'neuro_sofa': 'max',
        'hepatic_sofa': 'max',
        'renal_sofa': 'max',
        'coag_sofa': 'max'
    }).reset_index()

    comp_cols = ['resp_sofa', 'cardio_sofa', 'neuro_sofa', 'hepatic_sofa', 'renal_sofa', 'coag_sofa']
    daily['components_present'] = daily[comp_cols].notna().sum(axis=1)

    if impute_missing_as_zero:
        daily['total_sofa'] = daily[comp_cols].fillna(0).sum(axis=1)
    else:
        daily['total_sofa'] = daily[comp_cols].sum(axis=1, min_count=min_components)
        daily.loc[daily['components_present'] < min_components, 'total_sofa'] = np.nan

    missing_rate = daily[comp_cols].isna().mean().round(2)
    print(f"Missingness per component: {missing_rate.to_dict()}")

    return daily[
        ['person_id', 'visit_occurrence_id', 'chartdate', 'total_sofa', 'components_present'] + comp_cols
    ]