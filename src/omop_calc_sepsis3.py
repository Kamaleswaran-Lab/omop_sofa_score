"""
omop_calc_sepsis3.py
Sepsis-3 calculator with pre-infection baseline
"""
import pandas as pd
from datetime import timedelta

class Sepsis3Calculator:
    def __init__(self):
        pass
    
    def find_suspected_infections(self, antibiotics_df, cultures_df, max_hours_apart=72):
        """Find suspected infections: antibiotics + culture within 72h"""
        infections = []
        
        for _, abx in antibiotics_df.iterrows():
            window_start = abx['drug_exposure_start_datetime'] - timedelta(hours=24)
            window_end = abx['drug_exposure_start_datetime'] + timedelta(hours=max_hours_apart)
            
            matching_cultures = cultures_df[
                (cultures_df['person_id'] == abx['person_id']) &
                (cultures_df['specimen_datetime'] >= window_start) &
                (cultures_df['specimen_datetime'] <= window_end)
            ]
            
            if not matching_cultures.empty:
                infections.append({
                    'person_id': abx['person_id'],
                    'infection_onset': abx['drug_exposure_start_datetime'],
                    'antibiotic_concept_id': abx['drug_concept_id'],
                    'culture_datetime': matching_cultures.iloc[0]['specimen_datetime']
                })
        
        return pd.DataFrame(infections)

    def calculate_sepsis3_enhanced(self, sofa_df, infection_df):
        """v4.5: 96h culture, 48h collapse, ICU onset"""
        # Merge SOFA with infections
        merged = infection_df.merge(sofa_df, on='person_id', how='left')
    
        # Calculate baseline (72h pre) and peak (48h post)
        merged['baseline_sofa'] = merged.apply(
            lambda r: sofa_df[(sofa_df.charttime >= r.baseline_start) &
                             (sofa_df.charttime <= r.infection_onset)]['total_sofa'].min(), axis=1)
        merged['peak_sofa'] = merged.apply(
            lambda r: sofa_df[(sofa_df.charttime >= r.infection_onset) &
                             (sofa_df.charttime <= r.organ_dysfunction_end)]['total_sofa'].max(), axis=1)
    
        merged['delta_sofa'] = merged['peak_sofa'] - merged['baseline_sofa']
        sepsis = merged[merged['delta_sofa'] >= 2].copy()
    
        # 48h collapse
        sepsis = sepsis.sort_values(['person_id','infection_onset'])
        sepsis['prev'] = sepsis.groupby('person_id')['infection_onset'].shift()
        sepsis = sepsis[sepsis['prev'].isna() |
                       (sepsis['infection_onset'] - sepsis['prev'] > pd.Timedelta(hours=48))]
    
        return sepsis
    
    def calculate_sepsis3(self, infections_df, sofa_scores_df):
        """Calculate Sepsis-3 with pre-infection baseline"""
        sepsis_cases = []
        
        for _, infection in infections_df.iterrows():
            person_id = infection['person_id']
            infection_time = infection['infection_onset']
            
            baseline_window_start = infection_time - timedelta(hours=72)
            baseline_window_end = infection_time - timedelta(hours=1)
            
            baseline_sofa = sofa_scores_df[
                (sofa_scores_df['person_id'] == person_id) &
                (sofa_scores_df['charttime'] >= baseline_window_start) &
                (sofa_scores_df['charttime'] <= baseline_window_end)
            ]['total_sofa'].max()
            
            if pd.isna(baseline_sofa):
                baseline_sofa = 0
            
            window_start = infection_time - timedelta(hours=48)
            window_end = infection_time + timedelta(hours=24)
            
            window_max = sofa_scores_df[
                (sofa_scores_df['person_id'] == person_id) &
                (sofa_scores_df['charttime'] >= window_start) &
                (sofa_scores_df['charttime'] <= window_end)
            ]['total_sofa'].max()
            
            delta = window_max - baseline_sofa if not pd.isna(window_max) else 0
            
            if delta >= 2:
                sepsis_cases.append({
                    'person_id': person_id,
                    'infection_onset': infection_time,
                    'baseline_sofa': baseline_sofa,
                    'peak_sofa': window_max,
                    'delta_sofa': delta,
                    'sepsis_onset': infection_time
                })
        
        return pd.DataFrame(sepsis_cases)
    
    def calculate_septic_shock(self, sepsis_cases_df, vasopressors_df, lactate_df):
        """Identify septic shock: sepsis + vasopressor + lactate >2"""
        shock_cases = []
        
        for _, case in sepsis_cases_df.iterrows():
            person_id = case['person_id']
            sepsis_time = case['sepsis_onset']
            
            has_vasopressor = not vasopressors_df[
                (vasopressors_df['person_id'] == person_id) &
                (vasopressors_df['drug_exposure_start_datetime'] >= sepsis_time) &
                (vasopressors_df['drug_exposure_start_datetime'] <= sepsis_time + timedelta(hours=24))
            ].empty
            
            lactate = lactate_df[
                (lactate_df['person_id'] == person_id) &
                (lactate_df['measurement_datetime'] >= sepsis_time) &
                (lactate_df['measurement_datetime'] <= sepsis_time + timedelta(hours=24))
            ]['value_as_number'].max()
            
            if has_vasopressor and not pd.isna(lactate) and lactate > 2.0:
                shock_cases.append({
                    'person_id': person_id,
                    'shock_onset': sepsis_time,
                    'lactate': lactate
                })
        
        return pd.DataFrame(shock_cases)
