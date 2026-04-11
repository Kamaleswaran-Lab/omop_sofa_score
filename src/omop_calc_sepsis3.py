import pandas as pd
import numpy as np

def compute_suspected_infection(cdm, ancestor_df=None):
    from omop_utils import get_cultures, get_antibiotics
    cultures = get_cultures(cdm, ancestor_df)
    antibiotics = get_antibiotics(cdm, ancestor_df)
    if cultures.empty or antibiotics.empty:
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','suspicion_time'])
    suspected = []
    for _, cult in cultures.iterrows():
        abx_after = antibiotics[(antibiotics['person_id'] == cult['person_id']) & (antibiotics['visit_occurrence_id'] == cult['visit_occurrence_id']) & (antibiotics['abx_time'] >= cult['culture_time']) & (antibiotics['abx_time'] <= cult['culture_time'] + pd.Timedelta(hours=72))]
        abx_before = antibiotics[(antibiotics['person_id'] == cult['person_id']) & (antibiotics['visit_occurrence_id'] == cult['visit_occurrence_id']) & (antibiotics['abx_time'] < cult['culture_time']) & (antibiotics['abx_time'] >= cult['culture_time'] - pd.Timedelta(hours=24))]
        if not abx_after.empty or not abx_before.empty:
            times = [cult['culture_time']]
            if not abx_after.empty: times.append(abx_after['abx_time'].min())
            if not abx_before.empty: times.append(abx_before['abx_time'].min())
            suspicion_time = min(times)
            suspected.append({'person_id': cult['person_id'], 'visit_occurrence_id': cult['visit_occurrence_id'], 'suspicion_time': suspicion_time, 'culture_time': cult['culture_time']})
    result = pd.DataFrame(suspected).drop_duplicates()
    print(f"Found {len(result)} suspected infection events")
    return result

def evaluate_sepsis3(daily_sofa, suspected_infections, cdm):
    if daily_sofa.empty or suspected_infections.empty:
        return pd.DataFrame()
    results = []
    for _, susp in suspected_infections.iterrows():
        pid = susp['person_id']
        vid = susp['visit_occurrence_id']
        susp_time = susp['suspicion_time']
        patient_sofa = daily_sofa[(daily_sofa['person_id'] == pid) & (daily_sofa['visit_occurrence_id'] == vid)].copy()
        if patient_sofa.empty: continue
        patient_sofa['hours_from_inf'] = (pd.to_datetime(patient_sofa['chartdate']) - susp_time).dt.total_seconds() / 3600
        baseline_window = patient_sofa[patient_sofa['hours_from_inf'] < -24]
        baseline_sofa = baseline_window['total_sofa'].min() if not baseline_window.empty else 0
        acute_window = patient_sofa[(patient_sofa['hours_from_inf'] >= -48) & (patient_sofa['hours_from_inf'] <= 24)]
        acute_valid = acute_window[acute_window['components_present'] >= 1]
        if acute_valid.empty: continue
        max_sofa = acute_valid['total_sofa'].max()
        delta_sofa = max_sofa - baseline_sofa
        results.append({'person_id': pid, 'visit_occurrence_id': vid, 'suspicion_time': susp_time, 'baseline_sofa': baseline_sofa, 'max_sofa_acute': max_sofa, 'delta_sofa': delta_sofa, 'sepsis3': delta_sofa >= 2})
    result_df = pd.DataFrame(results)
    if not result_df.empty:
        print(f"Sepsis-3 evaluation: {result_df['sepsis3'].sum()} / {len(result_df)} meet criteria (delta>=2)")
        print(f"Using components_present >=1 (ward-appropriate, was >=4 for ICU)")
    return result_df
