"""
omop_calc_sepsis3.py - Sepsis-3 with pre-infection baseline
"""
import pandas as pd
from datetime import timedelta

class Sepsis3Calculator:
    def find_suspected_infections(self, antibiotics_df, cultures_df, max_hours_apart=72):
        infections = []
        for _, abx in antibiotics_df.iterrows():
            start = abx['drug_exposure_start_datetime'] - timedelta(hours=24)
            end = abx['drug_exposure_start_datetime'] + timedelta(hours=max_hours_apart)
            matches = cultures_df[
                (cultures_df['person_id'] == abx['person_id']) &
                (cultures_df['specimen_datetime'] >= start) &
                (cultures_df['specimen_datetime'] <= end)
            ]
            if not matches.empty:
                infections.append({
                    'person_id': abx['person_id'],
                    'infection_onset': abx['drug_exposure_start_datetime'],
                    'antibiotic_concept_id': abx['drug_concept_id']
                })
        return pd.DataFrame(infections)
    
    def calculate_sepsis3(self, infections_df, sofa_df):
        cases = []
        for _, inf in infections_df.iterrows():
            pid = inf['person_id']
            t0 = inf['infection_onset']
            baseline = sofa_df[
                (sofa_df['person_id'] == pid) &
                (sofa_df['charttime'] >= t0 - timedelta(hours=72)) &
                (sofa_df['charttime'] <= t0 - timedelta(hours=1))
            ]['total_sofa'].max()
            baseline = 0 if pd.isna(baseline) else baseline
            window_max = sofa_df[
                (sofa_df['person_id'] == pid) &
                (sofa_df['charttime'] >= t0 - timedelta(hours=48)) &
                (sofa_df['charttime'] <= t0 + timedelta(hours=24))
            ]['total_sofa'].max()
            delta = window_max - baseline if not pd.isna(window_max) else 0
            if delta >= 2:
                cases.append({
                    'person_id': pid, 'infection_onset': t0,
                    'baseline_sofa': baseline, 'peak_sofa': window_max,
                    'delta_sofa': delta
                })
        return pd.DataFrame(cases)
