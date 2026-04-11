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

    if cultures.empty or abx.empty:
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','t_inf','culture_time','abx_time'])

    abx_course = abx.groupby(['person_id','visit_occurrence_id','abx_time']).size().reset_index(name='doses')
    abx_valid = abx.merge(abx_course, on=['person_id','visit_occurrence_id','abx_time'], how='left')

    infection = cultures.merge(abx_valid, on=['person_id','visit_occurrence_id'], how='inner')
    infection['time_diff_h'] = (infection['abx_time'] - infection['culture_time']).dt.total_seconds() / 3600

    valid = infection[(infection['time_diff_h'] >= -24) & (infection['time_diff_h'] <= 72)].copy()
    valid['t_inf'] = valid[['culture_time','abx_time']].min(axis=1)

    first_inf = valid.loc[valid.groupby(['person_id','visit_occurrence_id'])['t_inf'].idxmin()]
    return first_inf[['person_id','visit_occurrence_id','t_inf','culture_time','abx_time']]

def get_chronic_organ_dysfunction(cdm, ancestor_df=None):
    co = cdm['condition_occurrence']
    liver_cirr = expand_concepts(ancestor_df, [4032015])
    esrd = expand_concepts(ancestor_df, [4030516])
    chronic = co[co['condition_concept_id'].isin(liver_cirr + esrd)]
    chronic_flag = chronic.groupby('person_id').size().reset_index(name='chronic_count')
    chronic_flag['has_chronic_organ_dysfunction'] = 1
    return chronic_flag[['person_id','has_chronic_organ_dysfunction']]

def evaluate_sepsis3(daily_sofa, suspected_infections, cdm=None, ancestor_df=None):
    daily_sofa['chart_datetime'] = pd.to_datetime(daily_sofa['chartdate']) + pd.Timedelta(hours=12)

    cohort = suspected_infections.merge(daily_sofa, on=['person_id','visit_occurrence_id'], how='inner')
    cohort['hours_from_inf'] = (cohort['chart_datetime'] - cohort['t_inf']).dt.total_seconds() / 3600

    baseline_window = cohort[(cohort['hours_from_inf'] >= -72) & (cohort['hours_from_inf'] < -1)]
    baseline = baseline_window.sort_values('hours_from_inf').groupby(['person_id','visit_occurrence_id']).last().reset_index()
    baseline = baseline[['person_id','visit_occurrence_id','total_sofa','components_present']].rename(
        columns={'total_sofa':'baseline_sofa','components_present':'baseline_components'}
    )

    acute_window = cohort[(cohort['hours_from_inf'] >= -48) & (cohort['hours_from_inf'] <= 24)]
    acute_valid = acute_window[acute_window['components_present'] >= 4]
    window_max = acute_valid.groupby(['person_id','visit_occurrence_id','t_inf'])['total_sofa'].max().reset_index()
    window_max = window_max.rename(columns={'total_sofa':'window_max_sofa'})

    sepsis_eval = window_max.merge(baseline, on=['person_id','visit_occurrence_id'], how='left')

    if cdm is not None:
        chronic = get_chronic_organ_dysfunction(cdm, ancestor_df)
        sepsis_eval = sepsis_eval.merge(chronic, on='person_id', how='left')
        sepsis_eval['has_chronic_organ_dysfunction'] = sepsis_eval['has_chronic_organ_dysfunction'].fillna(0)
    else:
        sepsis_eval['has_chronic_organ_dysfunction'] = 0

    sepsis_eval['baseline_assumed_zero'] = 0
    mask_unknown = sepsis_eval['baseline_sofa'].isna()
    mask_no_chronic = sepsis_eval['has_chronic_organ_dysfunction'] == 0
    sepsis_eval.loc[mask_unknown & mask_no_chronic, 'baseline_sofa'] = 0
    sepsis_eval.loc[mask_unknown & mask_no_chronic, 'baseline_assumed_zero'] = 1

    sepsis_eval['baseline_valid'] = ~sepsis_eval['baseline_sofa'].isna()

    sepsis_eval['delta_sofa'] = sepsis_eval['window_max_sofa'] - sepsis_eval['baseline_sofa']
    sepsis_eval['is_sepsis3'] = np.where(
        (sepsis_eval['baseline_valid']) & (sepsis_eval['delta_sofa'] >= 2),
        1, 0
    )

    return sepsis_eval[[
        'person_id','visit_occurrence_id','t_inf','baseline_sofa','window_max_sofa',
        'delta_sofa','is_sepsis3','baseline_assumed_zero','has_chronic_organ_dysfunction','baseline_valid'
    ]]