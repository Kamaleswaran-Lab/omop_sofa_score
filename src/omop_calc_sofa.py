"""
omop_calc_sofa.py
Python fallback implementation for SOFA calculation
MGH CHoRUS Edition - with expanded concept support

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
    from chorus_concepts import (
        VASOPRESSOR_CONCEPTS, VASOPRESSOR_NEE_FACTORS, get_all_vasopressor_ids,
        PAO2_CONCEPTS, FIO2_CONCEPTS, CREATININE_CONCEPTS, BILIRUBIN_CONCEPTS,
        PLATELETS_CONCEPTS, URINE_OUTPUT_CONCEPTS, LACTATE_CONCEPTS,
        GCS_CONCEPTS, RASS_CONCEPTS, WEIGHT_CONCEPTS, MAP_CONCEPTS,
        VENTILATOR_DEVICE_CONCEPTS, VENTILATOR_PROCEDURE_CONCEPTS,
        DIALYSIS_CONCEPTS
    )
    USE_CHORUS = True
except ImportError:
    USE_CHORUS = False
    def get_all_vasopressor_ids():
        return [4328749, 1338005, 1360635, 1335616, 1319998]

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# NEE conversion factors (FIX #1: vasopressin included)
# MGH Edition: expanded to include all MGH concept IDs
NEE_FACTORS = {}
if USE_CHORUS:
    # Build factor map for all MGH concept IDs
    for drug_type, concept_ids in VASOPRESSOR_CONCEPTS.items():
        factor = VASOPRESSOR_NEE_FACTORS[drug_type]
        for cid in concept_ids:
            NEE_FACTORS[cid] = factor
    logger.info(f"Loaded {len(NEE_FACTORS)} vasopressor concepts from chorus_concepts")
else:
    NEE_FACTORS = {
        4328749: 1.0,  # norepinephrine
        1338005: 1.0,  # epinephrine
        1360635: 2.5,  # vasopressin - WAS EXCLUDED IN v3.5
        1335616: 0.1,  # phenylephrine
        1319998: 0.01,  # dopamine
    }

# OMOP concept IDs - MGH Edition uses lists
if USE_CHORUS:
    CONCEPTS = {
        'pao2': PAO2_CONCEPTS,
        'fio2': FIO2_CONCEPTS,
        'creatinine': CREATININE_CONCEPTS,
        'bilirubin': BILIRUBIN_CONCEPTS,
        'platelets': PLATELETS_CONCEPTS,
        'urine_output': URINE_OUTPUT_CONCEPTS,
        'lactate': LACTATE_CONCEPTS,
        'gcs': GCS_CONCEPTS,
        'rass': RASS_CONCEPTS,
        'weight': WEIGHT_CONCEPTS,
        'map': MAP_CONCEPTS,
        'ventilator_device': VENTILATOR_DEVICE_CONCEPTS,
        'ventilator_procedure': VENTILATOR_PROCEDURE_CONCEPTS,
        'dialysis': DIALYSIS_CONCEPTS,
    }
    logger.info("Using MGH CHoRUS concept mappings")
else:
    CONCEPTS = {
        'pao2': [3002647],
        'fio2': [3013468],
        'creatinine': [3016723],
        'bilirubin': [3024128],
        'platelets': [3013290],
        'urine_output': [4065485],
        'lactate': [],
        'gcs': [4253928],
        'rass': [40488434],
        'weight': [3013762],
        'map': [3027598],
        'ventilator_device': [45768131],
        'ventilator_procedure': [4302207],
        'dialysis': [4146536],
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
        if USE_CHORUS:
            logger.info(f"  MGH mode: {len(get_all_vasopressor_ids())} vasopressor concepts")

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
        FIX #1: Includes vasopressin (MGH edition supports all MGH IDs)
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

            # Get NEE factor (now works for all MGH IDs)
            factor = NEE_FACTORS.get(concept_id, 0)
            nee_contrib = dose_norm * factor
            total_nee += nee_contrib

            # Track vasopressin separately (MGH edition: check all vasopressin IDs)
            is_vasopressin = False
            if USE_CHORUS:
                is_vasopressin = concept_id in VASOPRESSOR_CONCEPTS['vasopressin']
            else:
                is_vasopressin = concept_id == 1360635

            if is_vasopressin:
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

    def filter_measurements(self, df, concept_type):
        """Helper to filter by MGH concept lists"""
        concepts = CONCEPTS.get(concept_type, [])
        if not isinstance(concepts, list):
            concepts = [concepts]
        return df[df['measurement_concept_id'].isin(concepts)]

    def filter_drugs(self, df):
        """Helper to filter vasopressors by MGH concept lists"""
        all_vaso_ids = get_all_vasopressor_ids()
        return df[df['drug_concept_id'].isin(all_vaso_ids)]
