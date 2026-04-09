import pandas as pd
import numpy as np
from omop_utils import OHDSI_CONCEPTS, get_descendants

def compute_suspected_infection(cdm, cdm_ancestor=None):
    """
    Identifies the t_inf window based on concurrent cultures and antibiotics.
    """
    abx_concepts = get_descendants(cdm_ancestor, OHDSI_CONCEPTS['antibiotic_ingredients'])
    
    # 1. Extract Cultures
    cultures = cdm['measurement'][cdm['measurement']['measurement_concept_id'].isin(OHDSI_CONCEPTS['cultures'])][['person_id', 'visit_occurrence_id', 'measurement_datetime']]
    cultures = cultures.rename(columns={'measurement_datetime': 'culture_time'})
    cultures['culture_time'] = pd.to_datetime(cultures['culture_time'])

    # 2. Extract Antibiotics
    abx = cdm['drug_exposure'][cdm['drug_exposure']['drug_concept_id'].isin(abx_concepts)][['person_id', 'visit_occurrence_id', 'drug_exposure_start_datetime']]
    abx = abx.rename(columns={'drug_exposure_start_datetime': 'abx_time'})
    abx['abx_time'] = pd.to_datetime(abx['abx_time'])

    # 3. Join and calculate temporal difference
    infection_df = cultures.merge(abx, on=['person_id', 'visit_occurrence_id'], how='inner')
    infection_df['time_diff'] = (infection_df['abx_time'] - infection_df['culture_time']).dt.total_seconds() / 3600.0
    
    # Valid window: Abx given 24h before to 72h after culture
    valid_infections = infection_df[(infection_df['time_diff'] >= -24) & (infection_df['time_diff'] <= 72)].copy()
    valid_infections['t_inf'] = valid_infections[['culture_time', 'abx_time']].min(axis=1)
    
    # Return the first incidence of suspected infection per encounter
    suspected_infections = valid_infections.loc[valid_infections.groupby(['person_id', 'visit_occurrence_id'])['t_inf'].idxmin()]
    return suspected_infections[['person_id', 'visit_occurrence_id', 't_inf']]


def evaluate_sepsis3(daily_sofa, suspected_infections):
    """
    Evaluates Sepsis-3 criteria (Delta SOFA >= 2) within the clinical window.
    
    Parameters:
    - daily_sofa: DataFrame output from omop_calc_sofa.py 
                  (Must contain person_id, visit_occurrence_id, chartdate, total_sofa)
    - suspected_infections: DataFrame output from compute_suspected_infection()
    """
    daily_sofa['chart_datetime'] = pd.to_datetime(daily_sofa['chartdate'])
    
    # Merge longitudinal SOFA scores with the index infection time
    cohort = suspected_infections.merge(daily_sofa, on=['person_id', 'visit_occurrence_id'], how='inner')
    
    # Calculate offset from t_inf in hours
    cohort['hours_from_inf'] = (cohort['chart_datetime'] - cohort['t_inf']).dt.total_seconds() / 3600.0
    
    # Define Baseline: Max SOFA prior to -48h before infection
    baseline_df = cohort[cohort['hours_from_inf'] < -48].groupby(['person_id', 'visit_occurrence_id'])['total_sofa'].max().reset_index()
    baseline_df = baseline_df.rename(columns={'total_sofa': 'baseline_sofa'})
    
    # Define Acute Window: Max SOFA from -48h to +24h around infection
    window_df = cohort[(cohort['hours_from_inf'] >= -48) & (cohort['hours_from_inf'] <= 24)]
    max_window_df = window_df.groupby(['person_id', 'visit_occurrence_id', 't_inf'])['total_sofa'].max().reset_index()
    max_window_df = max_window_df.rename(columns={'total_sofa': 'window_max_sofa'})
    
    # Assess Delta SOFA
    sepsis3_eval = max_window_df.merge(baseline_df, on=['person_id', 'visit_occurrence_id'], how='left')
    
    # Sepsis-3 Guideline: If pre-existing organ dysfunction is unknown, assume baseline is 0
    sepsis3_eval['baseline_sofa'] = sepsis3_eval['baseline_sofa'].fillna(0) 
    
    sepsis3_eval['delta_sofa'] = sepsis3_eval['window_max_sofa'] - sepsis3_eval['baseline_sofa']
    sepsis3_eval['is_sepsis3'] = np.where(sepsis3_eval['delta_sofa'] >= 2, 1, 0)

    return sepsis3_eval
