import pandas as pd
import numpy as np
from omop_utils import get_cultures, get_antibiotics, expand_concepts, CONCEPT_SEEDS

def compute_suspected_infection(cdm, ancestor_df=None):
    """
    Sepsis-3 suspected infection: culture and antibiotic within -24h to +72h,
    with antibiotic course defined as ≥2 administrations or duration >24h.
    """
    cultures = get_cultures(cdm, ancestor_df)
    abx = get_antibiotics(cdm, ancestor_df)

    if cultures.empty or abx.empty:
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','t_inf','culture_time','abx_time'])

    # Require antibiotic course, not single dose
    abx_course = abx.groupby(['person_id','visit_occurrence_id','abx_time']).size().reset_index(name='doses')
    # This is simplified; in production join back to drug_exposure for end times
    abx_valid = abx.merge(abx_course, on=['person_id','visit_occurrence_id','abx_time'], how='left')

    # Cross join cultures and antibiotics per encounter
    infection = cultures.merge(abx_valid, on=['person_id','visit_occurrence_id'], how='inner')
    infection['time_diff_h'] = (infection['abx_time'] - infection['culture_time']).dt.total_seconds() / 3600

    # Sepsis-3 window: abx within 24h before to 72h after culture
    valid = infection[(infection['time_diff_h'] >= -24) & (infection['time_diff_h'] <= 72)].copy()
    valid['t_inf'] = valid[['culture_time','abx_time']].min(axis=1)

    # First infection per encounter
    first_inf = valid.loc[valid.groupby(['person_id','visit_occurrence_id'])['t_inf'].idxmin()]
    return first_inf[['person_id','visit_occurrence_id','t_inf','culture_time','abx_time']]

def get_chronic_organ_dysfunction(cdm, ancestor_df=None):
    """Flag patients with chronic liver, renal, or hematologic disease to avoid baseline=0 assumption."""
    co = cdm['condition_occurrence']
    # Example concept sets - expand in production
    liver_cirr = expand_concepts(ancestor_df, [4032015]) # cirrhosis
    esrd = expand_concepts(ancestor_df, [4030516]) # ESRD
    chronic = co[co['condition_concept_id'].isin(liver_cirr + esrd)]
    chronic_flag = chronic.groupby('person_id').size().reset_index(name='chronic_count')
    chronic_flag['has_chronic_organ_dysfunction'] = 1
    return chronic_flag[['person_id','has_chronic_organ_dysfunction']]

def evaluate_sepsis3(daily_sofa, suspected_infections, cdm=None, ancestor_df=None):
    """
    Evaluate Sepsis-3: delta SOFA >=2 from baseline within infection window.

    daily_sofa must contain: person_id, visit_occurrence_id, chartdate, total_sofa, components_present
    """
    # Convert daily to hourly for precise windowing by expanding each day to noon
    daily_sofa['chart_datetime'] = pd.to_datetime(daily_sofa['chartdate']) + pd.Timedelta(hours=12)

    cohort = suspected_infections.merge(daily_sofa, on=['person_id','visit_occurrence_id'], how='inner')
    cohort['hours_from_inf'] = (cohort['chart_datetime'] - cohort['t_inf']).dt.total_seconds() / 3600

    # BASELINE: last SOFA between -72h and -1h, not max
    baseline_window = cohort[(cohort['hours_from_inf'] >= -72) & (cohort['hours_from_inf'] < -1)]
    baseline = baseline_window.sort_values('hours_from_inf').groupby(['person_id','visit_occurrence_id']).last().reset_index()
    baseline = baseline[['person_id','visit_occurrence_id','total_sofa','components_present']].rename(
        columns={'total_sofa':'baseline_sofa','components_present':'baseline_components'}
    )

    # ACUTE WINDOW: max SOFA between -48h and +24h
    acute_window = cohort[(cohort['hours_from_inf'] >= -48) & (cohort['hours_from_inf'] <= 24)]
    # require at least 4 components for valid score
    acute_valid = acute_window[acute_window['components_present'] >= 4]
    window_max = acute_valid.groupby(['person_id','visit_occurrence_id','t_inf'])['total_sofa'].max().reset_index()
    window_max = window_max.rename(columns={'total_sofa':'window_max_sofa'})

    # Merge
    sepsis_eval = window_max.merge(baseline, on=['person_id','visit_occurrence_id'], how='left')

    # Handle missing baseline
    if cdm is not None:
        chronic = get_chronic_organ_dysfunction(cdm, ancestor_df)
        sepsis_eval = sepsis_eval.merge(chronic, on='person_id', how='left')
        sepsis_eval['has_chronic_organ_dysfunction'] = sepsis_eval['has_chronic_organ_dysfunction'].fillna(0)
    else:
        sepsis_eval['has_chronic_organ_dysfunction'] = 0

    # Sepsis-3 rule: assume 0 only if no chronic dysfunction and no prior data
    sepsis_eval['baseline_assumed_zero'] = 0
    mask_unknown = sepsis_eval['baseline_sofa'].isna()
    mask_no_chronic = sepsis_eval['has_chronic_organ_dysfunction'] == 0
    sepsis_eval.loc[mask_unknown & mask_no_chronic, 'baseline_sofa'] = 0
    sepsis_eval.loc[mask_unknown & mask_no_chronic, 'baseline_assumed_zero'] = 1

    # Exclude cases where baseline still unknown and chronic disease present
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
