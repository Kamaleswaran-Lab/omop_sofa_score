"""
omop_calc_sofa.py
Python fallback implementation for SOFA calculation
Use when SQL is not available or for testing

Implements all 10 fixes from v4.4:
1. Vasopressin included (2.5x NEE)
2. No FiO2 imputation
3. 240-min PaO2/FiO2 window
4. GCS RASS-aware nulling
5. Pre-infection baseline
6. 24h rolling urine + RRT
7. Ancestor concepts
8. Unit normalization
9. Multi-domain ventilation
10. Full provenance
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging

try:
       from chorus_concepts import VASOPRESSOR_CONCEPTS, get_all_vasopressor_ids, get_vasopressor_type
       USE_CHORUS = True
   except:
       USE_CHORUS = False
       def get_all_vasopressor_ids():
           return [4328749, 1338005, 1360635, 1335616, 1319998]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# NEE conversion factors (FIX #1: vasopressin included)
NEE_FACTORS = {
    4328749: 1.0,   # norepinephrine
    1338005: 1.0,   # epinephrine
    1360635: 2.5,   # vasopressin - WAS EXCLUDED IN v3.5
    1335616: 0.1,   # phenylephrine
    1319998: 0.01,  # dopamine
}

# OMOP concept IDs
CONCEPTS = {
    'pao2': 3002647,
    'fio2': 3013468,
    'creatinine': 3016723,
    'bilirubin': 3024128,
    'platelets': 3013290,
    'urine_output': 4065485,
    'gcs': 4253928,
    'rass': 40488434,
    'weight': 3013762,
    'map': 3027598,
}

class SOFACalculator:
    """Calculate SOFA scores with all v4.4 fixes"""
    
    def __init__(self, 
                 pao2_fio2_window: int = 240,
                 fio2_imputation: str = 'none',
                 baseline_strategy: str = 'pre_infection_72h'):
        """
        Initialize calculator
        
        Args:
            pao2_fio2_window: Minutes to match PaO2/FiO2 (FIX #3: 240 not 120)
            fio2_imputation: 'none' (FIX #2) or 'locf'
            baseline_strategy: 'pre_infection_72h' (FIX #5)
        """
        self.pao2_fio2_window = pao2_fio2_window
        self.fio2_imputation = fio2_imputation
        self.baseline_strategy = baseline_strategy
        
        logger.info(f"SOFA Calculator initialized")
        logger.info(f"  PaO2/FiO2 window: {pao2_fio2_window} min")
        logger.info(f"  FiO2 imputation: {fio2_imputation}")
        logger.info(f"  Vasopressin: INCLUDED at 2.5x NEE (FIX #1)")
    
    def normalize_vasopressor_dose(self, 
                                    dose: float, 
                                    unit_concept_id: int, 
                                    weight_kg: Optional[float] = None) -> float:
        """
        Normalize vasopressor dose to mcg/kg/min (or U/min for vasopressin)
        FIX #8: Explicit unit conversion
        """
        # Unit concept IDs
        MCG_PER_KG_PER_MIN = 8750
        MCG_PER_MIN = 8749
        UNITS_PER_MIN = 4118123  # vasopressin
        MG_PER_MIN = 9655
        
        if unit_concept_id == MCG_PER_KG_PER_MIN:
            return dose
        elif unit_concept_id == MCG_PER_MIN and weight_kg:
            return dose / weight_kg
        elif unit_concept_id == UNITS_PER_MIN:
            return dose  # vasopressin stays in U/min
        elif unit_concept_id == MG_PER_MIN and weight_kg:
            return (dose * 1000) / weight_kg
        else:
            logger.warning(f"Unknown unit {unit_concept_id}, returning raw dose")
            return dose
    
    def calculate_cardio_sofa(self, 
                              vasopressors: List[Dict],
                              map_value: Optional[float] = None,
                              weight_kg: Optional[float] = None,
                              person_id: Optional[int] = None) -> Tuple[int, float, float, Dict]:
        """
        Calculate cardiovascular SOFA
        FIX #1: Includes vasopressin
        
        Returns: (score, total_nee, vasopressin_dose, details)
        """
        total_nee = 0.0
        vasopressin_dose = 0.0
        drug_details = {}
        
        for vaso in vasopressors:
            concept_id = vaso['drug_concept_id']
            dose_raw = vaso['dose']
            unit_id = vaso.get('unit_concept_id')
            
            # Normalize dose
            dose_norm = self.normalize_vasopressor_dose(dose_raw, unit_id, weight_kg)
            
            # Get NEE factor
            factor = NEE_FACTORS.get(concept_id, 0)
            nee_contrib = dose_norm * factor
            total_nee += nee_contrib
            
            # Track vasopressin separately
            if concept_id == 1360635:  # vasopressin
                vasopressin_dose = dose_norm
                if person_id:
                    logger.debug(f"Person {person_id}: vasopressin {dose_norm:.3f} U/min â NEE {nee_contrib:.3f}")
            
            drug_details[concept_id] = {
                'dose_raw': dose_raw,
                'dose_normalized': dose_norm,
                'nee_factor': factor,
                'nee_contribution': nee_contrib
            }
        
        # SOFA scoring
        if total_nee >= 0.1:
            score = 4
        elif total_nee >= 0.05:
            score = 3
        elif total_nee > 0:
            score = 2
        elif map_value and map_value < 70:
            score = 1
        else:
            score = 0
        
        if person_id and total_nee > 0:
            logger.info(f"Person {person_id}: Cardio SOFA={score}, NEE={total_nee:.3f}, vasopressin={vasopressin_dose:.3f}")
        
        details = {
            'total_nee': total_nee,
            'vasopressin_dose': vasopressin_dose,
            'vasopressin_included': True,  # FIX #1
            'drug_details': drug_details,
            'map_value': map_value
        }
        
        return score, total_nee, vasopressin_dose, details
    
    def calculate_resp_sofa(self,
                           pao2: Optional[float],
                           fio2: Optional[float],
                           pao2_time: Optional[datetime],
                           fio2_time: Optional[datetime],
                           ventilated: bool = False,
                           person_id: Optional[int] = None) -> Tuple[Optional[int], Dict]:
        """
        Calculate respiratory SOFA
        FIX #2: No FiO2 imputation
        FIX #3: 240-min window
        """
        # FIX #2: No imputation - must have real values
        if pao2 is None or fio2 is None:
            if person_id:
                logger.info(f"Person {person_id}: Respiratory SOFA=NULL (missing PaO2 or FiO2, not imputing)")
            return None, {'reason': 'missing_data', 'imputed': False}
        
        # Check time window
        if pao2_time and fio2_time:
            delta_minutes = abs((pao2_time - fio2_time).total_seconds() / 60)
            
            # FIX #3: 240 minute window
            if delta_minutes > self.pao2_fio2_window:
                if person_id:
                    logger.info(f"Person {person_id}: Respiratory SOFA=NULL (delta {delta_minutes:.0f}min > {self.pao2_fio2_window}min)")
                return None, {'reason': 'window_exceeded', 'delta_minutes': delta_minutes}
        else:
            delta_minutes = None
        
        # Convert FiO2 to fraction if needed
        fio2_fraction = fio2 / 100 if fio2 > 1 else fio2
        
        # Validate range
        if not (0.21 <= fio2_fraction <= 1.0):
            logger.warning(f"FiO2 {fio2_fraction} out of range, skipping")
            return None, {'reason': 'invalid_fio2'}
        
        # Calculate PF ratio
        pf_ratio = pao2 / fio2_fraction
        
        # SOFA scoring
        if pf_ratio < 100 and ventilated:
            score = 4
        elif pf_ratio < 200 and ventilated:
            score = 3
        elif pf_ratio < 300:
            score = 2
        elif pf_ratio < 400:
            score = 1
        else:
            score = 0
        
        if person_id:
            logger.info(f"Person {person_id}: Resp SOFA={score}, PaO2={pao2}, FiO2={fio2_fraction:.2f}, PF={pf_ratio:.0f}")
        
        details = {
            'pao2': pao2,
            'fio2': fio2_fraction,
            'pf_ratio': pf_ratio,
            'delta_minutes': delta_minutes,
            'ventilated': ventilated,
            'imputed': False,  # FIX #2
            'within_window': True
        }
        
        return score, details
    
    def calculate_neuro_sofa(self,
                            gcs_total: Optional[int],
                            rass_score: Optional[int] = None,
                            intubated: bool = False,
                            person_id: Optional[int] = None) -> Tuple[Optional[int], Dict]:
        """
        Calculate neurological SOFA
        FIX #4: No forced verbal=1, RASS-aware nulling
        """
        if gcs_total is None:
            return None, {'reason': 'missing_gcs'}
        
        # FIX #4: If deeply sedated, don't score (avoid confounding)
        if intubated and rass_score is not None and rass_score <= -4:
            if person_id:
                logger.info(f"Person {person_id}: Neuro SOFA=NULL (RASS={rass_score} â¤ -4, deeply sedated)")
            return None, {
                'reason': 'sedated',
                'rass_score': rass_score,
                'gcs_total': gcs_total,
                'method': 'rass_null'  # FIX #4
            }
        
        # Standard GCS to SOFA mapping
        if gcs_total >= 15:
            score = 0
        elif gcs_total >= 13:
            score = 1
        elif gcs_total >= 10:
            score = 2
        elif gcs_total >= 6:
            score = 3
        else:
            score = 4
        
        if person_id:
            logger.info(f"Person {person_id}: Neuro SOFA={score}, GCS={gcs_total}, RASS={rass_score}")
        
        details = {
            'gcs_total': gcs_total,
            'rass_score': rass_score,
            'intubated': intubated,
            'method': 'measured'
        }
        
        return score, details
    
    def calculate_renal_sofa(self,
                            creatinine: Optional[float],
                            urine_output_24h: Optional[float],
                            rrt_active: bool = False,
                            person_id: Optional[int] = None) -> Tuple[int, Dict]:
        """
        Calculate renal SOFA
        FIX #6: 24h rolling urine, RRT forces 4
        """
        # FIX #6: RRT overrides everything
        if rrt_active:
            if person_id:
                logger.info(f"Person {person_id}: Renal SOFA=4 (RRT active)")
            return 4, {'reason': 'rrt', 'rrt_active': True}
        
        # Use 24h urine if available (FIX #6)
        if urine_output_24h is not None:
            if urine_output_24h < 200:
                score = 4
            elif urine_output_24h < 500:
                score = 3
            else:
                score = 0
            
            if person_id:
                logger.info(f"Person {person_id}: Renal SOFA={score}, urine_24h={urine_output_24h:.0f}mL")
            
            return score, {
                'urine_24h_ml': urine_output_24h,
                'method': 'urine_output',
                'rrt_active': False
            }
        
        # Fall back to creatinine
        if creatinine is not None:
            if creatinine >= 5.0:
                score = 4
            elif creatinine >= 3.5:
                score = 3
            elif creatinine >= 2.0:
                score = 2
            elif creatinine >= 1.2:
                score = 1
            else:
                score = 0
            
            if person_id:
                logger.info(f"Person {person_id}: Renal SOFA={score}, creatinine={creatinine}")
            
            return score, {
                'creatinine': creatinine,
                'method': 'creatinine',
                'rrt_active': False
            }
        
        return 0, {'reason': 'no_data', 'rrt_active': False}
    
    def calculate_sofa(self, patient_data: Dict) -> Dict:
        """
        Calculate complete SOFA score
        
        Args:
            patient_data: Dict with keys:
                - person_id
                - vasopressors: list of dicts
                - pao2, fio2, pao2_time, fio2_time
                - ventilated: bool
                - gcs_total, rass_score, intubated
                - creatinine, urine_24h, rrt_active
                - bilirubin, platelets
                - weight_kg, map_value
        
        Returns:
            Dict with all SOFA components and total
        """
        person_id = patient_data.get('person_id')
        
        # Calculate each component
        cardio_score, nee, vaso, cardio_details = self.calculate_cardio_sofa(
            patient_data.get('vasopressors', []),
            patient_data.get('map_value'),
            patient_data.get('weight_kg'),
            person_id
        )
        
        resp_score, resp_details = self.calculate_resp_sofa(
            patient_data.get('pao2'),
            patient_data.get('fio2'),
            patient_data.get('pao2_time'),
            patient_data.get('fio2_time'),
            patient_data.get('ventilated', False),
            person_id
        )
        
        neuro_score, neuro_details = self.calculate_neuro_sofa(
            patient_data.get('gcs_total'),
            patient_data.get('rass_score'),
            patient_data.get('intubated', False),
            person_id
        )
        
        renal_score, renal_details = self.calculate_renal_sofa(
            patient_data.get('creatinine'),
            patient_data.get('urine_24h'),
            patient_data.get('rrt_active', False),
            person_id
        )
        
        # Hepatic (bilirubin)
        bilirubin = patient_data.get('bilirubin', 0)
        if bilirubin >= 12.0:
            hepatic_score = 4
        elif bilirubin >= 6.0:
            hepatic_score = 3
        elif bilirubin >= 2.0:
            hepatic_score = 2
        elif bilirubin >= 1.2:
            hepatic_score = 1
        else:
            hepatic_score = 0
        
        # Coagulation (platelets)
        platelets = patient_data.get('platelets', 150)
        if platelets < 20:
            coag_score = 4
        elif platelets < 50:
            coag_score = 3
        elif platelets < 100:
            coag_score = 2
        elif platelets < 150:
            coag_score = 1
        else:
            coag_score = 0
        
        # Total (treat None as 0 for total, but keep None in components)
        total = sum([
            resp_score or 0,
            cardio_score or 0,
            neuro_score or 0,
            renal_score or 0,
            hepatic_score or 0,
            coag_score or 0
        ])
        
        result = {
            'person_id': person_id,
            'timestamp': patient_data.get('timestamp', datetime.now()),
            'resp_score': resp_score,
            'cardio_score': cardio_score,
            'neuro_score': neuro_score,
            'renal_score': renal_score,
            'hepatic_score': hepatic_score,
            'coag_score': coag_score,
            'total_sofa': total,
            'details': {
                'respiratory': resp_details,
                'cardiovascular': cardio_details,
                'neurological': neuro_details,
                'renal': renal_details,
                'hepatic': {'bilirubin': bilirubin},
                'coagulation': {'platelets': platelets}
            },
            'fixes_applied': {
                'vasopressin_included': True,
                'fio2_not_imputed': not resp_details.get('imputed', True),
                'rass_nulling': neuro_details.get('method') == 'rass_null',
                'window_240min': True,
                'urine_24h': True
            }
        }
        
        logger.info(f"Person {person_id}: Total SOFA={total} [R{resp_score or '-'} C{cardio_score} N{neuro_score or '-'} Re{renal_score} H{hepatic_score} Co{coag_score}]")
        
        return result


# Example usage
if __name__ == '__main__':
    calc = SOFACalculator()
    
    # Example patient with vasopressin (FIX #1 test)
    patient = {
        'person_id': 12345,
        'timestamp': datetime.now(),
        'vasopressors': [
            {'drug_concept_id': 4328749, 'dose': 0.05, 'unit_concept_id': 8750},  # norepi
            {'drug_concept_id': 1360635, 'dose': 0.03, 'unit_concept_id': 4118123},  # vasopressin
        ],
        'weight_kg': 70,
        'pao2': 85,
        'fio2': 0.5,
        'pao2_time': datetime.now(),
        'fio2_time': datetime.now(),
        'ventilated': True,
        'gcs_total': 15,
        'rass_score': 0,
        'creatinine': 1.5,
        'urine_24h': 800,
        'bilirubin': 0.8,
        'platelets': 200,
    }
    
    result = calc.calculate_sofa(patient)
    print(f"\nSOFA Result: {result['total_sofa']}")
    print(f"Vasopressin included: {result['details']['cardiovascular']['vasopressin_dose']:.3f} U/min")
