"""
omop_calc_sepsis3.py
Sepsis-3 calculator with pre-infection baseline (FIX #5)

Implements Sepsis-3 criteria:
- Suspected infection (antibiotics + culture within 72h)
- SOFA increase â¥2 from baseline
- Baseline = minimum SOFA in 24-72h BEFORE infection (not last_available)
"""

import pandas as pd
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import logging

logger = logging.getLogger(__name__)

class Sepsis3Calculator:
    """Calculate Sepsis-3 cases with correct baseline"""
    
    def __init__(self, baseline_window_hours: int = 72):
        """
        Initialize calculator
        
        Args:
            baseline_window_hours: Hours before infection to look for baseline (FIX #5)
        """
        self.baseline_window = baseline_window_hours
        logger.info(f"Sepsis-3 Calculator initialized")
        logger.info(f"  Baseline window: {baseline_window_hours}h pre-infection (FIX #5)")
    
    def find_suspected_infections(self, 
                                   antibiotics: pd.DataFrame,
                                   cultures: pd.DataFrame,
                                   max_hours_apart: int = 72) -> pd.DataFrame:
        """
        Find suspected infections per Sepsis-3
        = antibiotics AND culture within 72 hours
        
        Args:
            antibiotics: DataFrame with person_id, abx_time
            cultures: DataFrame with person_id, culture_time
            max_hours_apart: Maximum hours between abx and culture
        
        Returns:
            DataFrame with infection episodes
        """
        logger.info(f"Finding suspected infections (abx + culture â¤{max_hours_apart}h)")
        
        infections = []
        
        for person_id in antibiotics['person_id'].unique():
            person_abx = antibiotics[antibiotics['person_id'] == person_id]
            person_cx = cultures[cultures['person_id'] == person_id]
            
            if person_cx.empty:
                continue
            
            for _, abx in person_abx.iterrows():
                # Find cultures within window
                time_diff = abs((person_cx['culture_time'] - abx['abx_time']).dt.total_seconds() / 3600)
                matching_cx = person_cx[time_diff <= max_hours_apart]
                
                if not matching_cx.empty:
                    # Take earliest culture
                    earliest_cx = matching_cx.loc[matching_cx['culture_time'].idxmin()]
                    
                    infection_time = min(abx['abx_time'], earliest_cx['culture_time'])
                    
                    infections.append({
                        'person_id': person_id,
                        'infection_onset': infection_time,
                        'abx_time': abx['abx_time'],
                        'culture_time': earliest_cx['culture_time'],
                        'hours_apart': abs((abx['abx_time'] - earliest_cx['culture_time']).total_seconds() / 3600),
                        'abx_first': abx['abx_time'] <= earliest_cx['culture_time']
                    })
        
        result = pd.DataFrame(infections)
        logger.info(f"Found {len(result)} suspected infections in {result['person_id'].nunique()} patients")
        
        return result
    
    def get_baseline_sofa(self,
                         sofa_scores: pd.DataFrame,
                         person_id: int,
                         infection_time: datetime,
                         window_start_hours: int = 72,
                         window_end_hours: int = 24) -> float:
        """
        Get baseline SOFA per Sepsis-3
        FIX #5: Use pre-infection window, not last_available
        
        Args:
            sofa_scores: DataFrame with person_id, charttime, total_sofa
            person_id: Patient ID
            infection_time: Time of infection onset
            window_start_hours: Start of baseline window (default 72h before)
            window_end_hours: End of baseline window (default 24h before)
        
        Returns:
            Baseline SOFA (minimum in window, or 0 if no data)
        """
        # Define baseline window: 24-72 hours BEFORE infection
        window_start = infection_time - timedelta(hours=window_start_hours)
        window_end = infection_time - timedelta(hours=window_end_hours)
        
        # Get SOFA scores in window
        person_sofa = sofa_scores[
            (sofa_scores['person_id'] == person_id) &
            (sofa_scores['charttime'] >= window_start) &
            (sofa_scores['charttime'] <= window_end)
        ]
        
        if person_sofa.empty:
            # No baseline data - assume 0 (per Sepsis-3 guidelines)
            logger.debug(f"Person {person_id}: No baseline SOFA in window, assuming 0")
            return 0.0
        
        baseline = person_sofa['total_sofa'].min()
        
        logger.debug(f"Person {person_id}: Baseline SOFA={baseline} "
                    f"(window {window_start} to {window_end}, n={len(person_sofa)})")
        
        return float(baseline)
    
    def calculate_sepsis3(self,
                         infections: pd.DataFrame,
                         sofa_scores: pd.DataFrame,
                         organ_dysfunction_window: int = 48) -> pd.DataFrame:
        """
        Calculate Sepsis-3 cases
        
        Args:
            infections: DataFrame from find_suspected_infections
            sofa_scores: DataFrame with hourly SOFA scores
            organ_dysfunction_window: Hours after infection to look for SOFA increase
        
        Returns:
            DataFrame with Sepsis-3 cases
        """
        logger.info(f"Calculating Sepsis-3 (SOFA increase â¥2 within {organ_dysfunction_window}h)")
        
        sepsis_cases = []
        
        for _, infection in infections.iterrows():
            person_id = infection['person_id']
            infection_time = infection['infection_onset']
            
            # Get baseline (FIX #5)
            baseline = self.get_baseline_sofa(sofa_scores, person_id, infection_time)
            
            # Look for SOFA increase in window after infection
            window_end = infection_time + timedelta(hours=organ_dysfunction_window)
            
            post_infection_sofa = sofa_scores[
                (sofa_scores['person_id'] == person_id) &
                (sofa_scores['charttime'] >= infection_time) &
                (sofa_scores['charttime'] <= window_end)
            ].copy()
            
            if post_infection_sofa.empty:
                continue
            
            # Calculate delta
            post_infection_sofa['delta_sofa'] = post_infection_sofa['total_sofa'] - baseline
            
            # Find first time delta â¥2
            sepsis_onset = post_infection_sofa[post_infection_sofa['delta_sofa'] >= 2]
            
            if not sepsis_onset.empty:
                first_sepsis = sepsis_onset.iloc[0]
                
                sepsis_cases.append({
                    'person_id': person_id,
                    'infection_onset': infection_time,
                    'sepsis_onset': first_sepsis['charttime'],
                    'baseline_sofa': baseline,
                    'peak_sofa': first_sepsis['total_sofa'],
                    'delta_sofa': first_sepsis['delta_sofa'],
                    'hours_to_sepsis': (first_sepsis['charttime'] - infection_time).total_seconds() / 3600,
                    'abx_time': infection['abx_time'],
                    'culture_time': infection['culture_time'],
                })
                
                logger.info(f"Person {person_id}: Sepsis-3 at {first_sepsis['charttime']}, "
                           f"baseline={baseline}, peak={first_sepsis['total_sofa']}, "
                           f"delta={first_sepsis['delta_sofa']}")
        
        result = pd.DataFrame(sepsis_cases)
        logger.info(f"Identified {len(result)} Sepsis-3 cases")
        
        return result
    
    def calculate_septic_shock(self,
                              sepsis_cases: pd.DataFrame,
                              vasopressors: pd.DataFrame,
                              lactate_values: pd.DataFrame) -> pd.DataFrame:
        """
        Identify septic shock (Sepsis-3)
        = Sepsis + vasopressor to maintain MAP â¥65 + lactate >2
        
        Args:
            sepsis_cases: DataFrame from calculate_sepsis3
            vasopressors: DataFrame with vasopressor administrations
            lactate_values: DataFrame with lactate measurements
        
        Returns:
            DataFrame with septic shock cases
        """
        logger.info("Identifying septic shock cases")
        
        shock_cases = []
        
        for _, sepsis in sepsis_cases.iterrows():
            person_id = sepsis['person_id']
            sepsis_time = sepsis['sepsis_onset']
            
            # Check for vasopressor within 6 hours of sepsis onset
            vaso_window_start = sepsis_time
            vaso_window_end = sepsis_time + timedelta(hours=6)
            
            person_vaso = vasopressors[
                (vasopressors['person_id'] == person_id) &
                (vasopressors['start_time'] >= vaso_window_start) &
                (vasopressors['start_time'] <= vaso_window_end)
            ]
            
            has_vasopressor = not person_vaso.empty
            
            # Check for lactate >2 within 6 hours
            lactate_window_start = sepsis_time - timedelta(hours=3)
            lactate_window_end = sepsis_time + timedelta(hours=3)
            
            person_lactate = lactate_values[
                (lactate_values['person_id'] == person_id) &
                (lactate_values['measurement_time'] >= lactate_window_start) &
                (lactate_values['measurement_time'] <= lactate_window_end) &
                (lactate_values['value'] > 2.0)
            ]
            
            has_hyperlactatemia = not person_lactate.empty
            
            if has_vasopressor and has_hyperlactatemia:
                shock_cases.append({
                    'person_id': person_id,
                    'sepsis_onset': sepsis_time,
                    'shock_onset': sepsis_time,  # Simplified
                    'vasopressor_used': True,
                    'max_lactate': person_lactate['value'].max(),
                    'baseline_sofa': sepsis['baseline_sofa'],
                    'peak_sofa': sepsis['peak_sofa'],
                })
                
                logger.info(f"Person {person_id}: Septic shock identified")
        
        result = pd.DataFrame(shock_cases)
        logger.info(f"Identified {len(result)} septic shock cases")
        
        return result


# Example usage
if __name__ == '__main__':
    # Create sample data
    antibiotics = pd.DataFrame({
        'person_id': [1, 1, 2],
        'abx_time': pd.to_datetime(['2023-01-01 10:00', '2023-01-05 14:00', '2023-01-02 09:00'])
    })
    
    cultures = pd.DataFrame({
        'person_id': [1, 1, 2],
        'culture_time': pd.to_datetime(['2023-01-01 08:00', '2023-01-05 16:00', '2023-01-02 10:00'])
    })
    
    sofa_scores = pd.DataFrame({
        'person_id': [1]*10 + [2]*10,
        'charttime': pd.date_range('2022-12-29', periods=10, freq='12H').tolist() * 2,
        'total_sofa': [0, 0, 1, 1, 2, 3, 5, 6, 5, 4, 1, 1, 1, 2, 2, 3, 4, 4, 3, 2]
    })
    
    calc = Sepsis3Calculator()
    
    infections = calc.find_suspected_infections(antibiotics, cultures)
    print(f"\nInfections found: {len(infections)}")
    print(infections)
    
    sepsis_cases = calc.calculate_sepsis3(infections, sofa_scores)
    print(f"\nSepsis-3 cases: {len(sepsis_cases)}")
    print(sepsis_cases)
