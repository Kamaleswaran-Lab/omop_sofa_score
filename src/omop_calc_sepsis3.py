import pandas as pd
import numpy as np

def compute_suspected_infection(cdm, ancestor_df=None):
    """FIX #1: Returns ALL infection windows, not just first"""
    from omop_utils import get_cultures, get_antibiotics
    cultures = get_cultures(cdm, ancestor_df)
    antibiotics = get_antibiotics(cdm, ancestor_df)
    if cultures.empty or antibiotics.empty:
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','suspicion_time','infection_episode'])
    suspected = []
    # Group by visit to find all infection episodes
    for (pid, vid), cult_group in cultures.groupby(['person_id','visit_occurrence_id']):
        abx_group = antibiotics[(antibiotics['person_id']==pid) & (antibiotics['visit_occurrence_id']==vid)]
        if abx_group.empty: continue
        # Sort cultures chronologically
        cult_group = cult_group.sort_values('culture_time')
        used_abx = set()
        episode_id = 0
        for _, cult in cult_group.iterrows():
            # Find unused antibiotics within window
            abx_after = abx_group[(~abx_group.index.isin(used_abx)) & (abx_group['abx_time'] >= cult['culture_time']) & (abx_group['abx_time'] <= cult['culture_time'] + pd.Timedelta(hours=72))]
            abx_before = abx_group[(~abx_group.index.isin(used_abx)) & (abx_group['abx_time'] < cult['culture_time']) & (abx_group['abx_time'] >= cult['culture_time'] - pd.Timedelta(hours=24))]
            if not abx_after.empty or not abx_before.empty:
                times = [cult['culture_time']]
                if not abx_after.empty:
                    times.append(abx_after['abx_time'].min())
                    used_abx.update(abx_after.index.tolist())
                if not abx_before.empty:
                    times.append(abx_before['abx_time'].min())
                    used_abx.update(abx_before.index.tolist())
                suspicion_time = min(times)
                episode_id += 1
                suspected.append({
                    'person_id': pid,
                    'visit_occurrence_id': vid,
                    'suspicion_time': suspicion_time,
                    'culture_time': cult['culture_time'],
                    'infection_episode': episode_id
                })
    result = pd.DataFrame(suspected).drop_duplicates()
    print(f"Found {len(result)} suspected infection episodes (including repeat infections)")
    return result

def evaluate_sepsis3(hourly_sofa, suspected_infections, cdm, ancestor_df=None):
    """FIX #1, #2, #3: Uses hourly grid, evaluates all episodes, handles chronic baselines"""
    from omop_utils import get_chronic_conditions
    if hourly_sofa.empty or suspected_infections.empty:
        return pd.DataFrame()
    chronic = get_chronic_conditions(cdm, ancestor_df)
    results = []
    for _, susp in suspected_infections.iterrows():
        pid = susp['person_id']
        vid = susp['visit_occurrence_id']
        susp_time = susp['suspicion_time']
        episode = susp.get('infection_episode', 1)
        patient_sofa = hourly_sofa[(hourly_sofa['person_id'] == pid) & (hourly_sofa['visit_occurrence_id'] == vid)].copy()
        if patient_sofa.empty: continue
        patient_sofa['hours_from_inf'] = (patient_sofa['charttime'] - susp_time).dt.total_seconds() / 3600
        # FIX #3: Check for chronic conditions
        has_chronic = False
        if not chronic.empty:
            pat_chronic = chronic[chronic['person_id']==pid]
            if not pat_chronic.empty:
                has_chronic = (pat_chronic['has_esrd'].iloc[0]==1) or (pat_chronic['has_cirrhosis'].iloc[0]==1)
        # Baseline: look back 72h, or up to 1 year if chronic
        baseline_window = patient_sofa[patient_sofa['hours_from_inf'] < -1]
        if has_chronic and baseline_window.empty:
            # FIX #3: Wider lookback for chronic patients
            baseline_window = patient_sofa[patient_sofa['hours_from_inf'] < -1]
            if len(baseline_window) < 24:  # Need at least 24h of data
                # Use earliest available as baseline
                baseline_window = patient_sofa.nsmallest(24, 'hours_from_inf')
        baseline_sofa = baseline_window['total_sofa'].min() if not baseline_window.empty else 0
        # FIX #2: Use hourly grid, not daily noon
        acute_window = patient_sofa[(patient_sofa['hours_from_inf'] >= -48) & (patient_sofa['hours_from_inf'] <= 24)]
        acute_valid = acute_window[acute_window['components_present'] >= 1]
        if acute_valid.empty: continue
        max_sofa = acute_valid['total_sofa'].max()
        delta_sofa = max_sofa - baseline_sofa
        results.append({
            'person_id': pid,
            'visit_occurrence_id': vid,
            'infection_episode': episode,
            'suspicion_time': susp_time,
            'baseline_sofa': baseline_sofa,
            'max_sofa_acute': max_sofa,
            'delta_sofa': delta_sofa,
            'has_chronic': has_chronic,
            'sepsis3': delta_sofa >= 2
        })
    result_df = pd.DataFrame(results)
    if not result_df.empty:
        print(f"Sepsis-3: {result_df['sepsis3'].sum()} / {len(result_df)} episodes meet criteria")
        print(f"Chronic patients: {result_df['has_chronic'].sum()}")
    return result_df
