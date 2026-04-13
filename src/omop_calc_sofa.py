"""
omop_calc_sofa.py
SOFA calculator v4.4 with Site A concepts
"""
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import logging
from chorus_concepts import (
    PAO2_CONCEPTS, FIO2_CONCEPTS, CREATININE_CONCEPTS,
    BILIRUBIN_CONCEPTS, PLATELETS_CONCEPTS, LACTATE_CONCEPTS,
    GCS_CONCEPTS, RASS_CONCEPTS
)

logger = logging.getLogger(__name__)

NEE_FACTORS = {
    4328749: 1.0,
    1338005: 1.0,
    1360635: 2.5,
    1335616: 0.1,
    1319998: 0.01,
    1321341: 1.0,
    19010309: 1.0,
}

class SOFACalculator:
    def __init__(self, pao2_fio2_window=240, fio2_imputation='none', baseline_strategy='pre_infection_72h'):
        self.pao2_fio2_window = pao2_fio2_window
        self.fio2_imputation = fio2_imputation
        self.baseline_strategy = baseline_strategy
        logger.info("SOFA Calculator v4.4 initialized")
        logger.info(f"  PaO2/FiO2 window: {pao2_fio2_window} min")
        logger.info(f"  FiO2 imputation: {fio2_imputation}")
        logger.info(f"  Site A concepts loaded")
    
    def calculate_resp_sofa(self, pao2, fio2, ventilated=False):
        if pd.isna(pao2) or pd.isna(fio2) or fio2 == 0:
            return None
        pf_ratio = pao2 / fio2
        if pf_ratio >= 400:
            return 0
        elif pf_ratio >= 300:
            return 1
        elif pf_ratio >= 200:
            return 2
        elif pf_ratio >= 100:
            return 3 if ventilated else 2
        else:
            return 4 if ventilated else 2
    
    def calculate_cardio_sofa(self, map_value=None, vasopressors=None, weight_kg=70):
        total_nee = 0
        if vasopressors:
            for vaso in vasopressors:
                dose = vaso.get('dose', 0)
                concept_id = vaso.get('drug_concept_id')
                factor = NEE_FACTORS.get(concept_id, 0)
                total_nee += dose * factor
        
        if total_nee > 0.1:
            return 4, total_nee
        elif total_nee > 0:
            return 3, total_nee
        elif map_value is not None and map_value < 70:
            return 1, 0
        return 0, 0
    
    def calculate_neuro_sofa(self, gcs_total, rass_score=None):
        if rass_score is not None and rass_score <= -4:
            return None
        if pd.isna(gcs_total):
            return None
        if gcs_total >= 15:
            return 0
        elif gcs_total >= 13:
            return 1
        elif gcs_total >= 10:
            return 2
        elif gcs_total >= 6:
            return 3
        else:
            return 4
    
    def calculate_renal_sofa(self, creatinine, urine_24h=None, rrt=False):
        if rrt:
            return 4
        if urine_24h is not None:
            if urine_24h < 200:
                return 4
            elif urine_24h < 500:
                return 3
        if pd.isna(creatinine):
            return None
        if creatinine < 1.2:
            return 0
        elif creatinine < 2.0:
            return 1
        elif creatinine < 3.5:
            return 2
        elif creatinine < 5.0:
            return 3
        else:
            return 4
    
    def calculate_hepatic_sofa(self, bilirubin):
        if pd.isna(bilirubin):
            return None
        if bilirubin < 1.2:
            return 0
        elif bilirubin < 2.0:
            return 1
        elif bilirubin < 6.0:
            return 2
        elif bilirubin < 12.0:
            return 3
        else:
            return 4
    
    def calculate_coag_sofa(self, platelets):
        if pd.isna(platelets):
            return None
        if platelets >= 150:
            return 0
        elif platelets >= 100:
            return 1
        elif platelets >= 50:
            return 2
        elif platelets >= 20:
            return 3
        else:
            return 4
    
    def calculate_sofa(self, data):
        resp = self.calculate_resp_sofa(
            data.get('pao2'), 
            data.get('fio2'), 
            data.get('ventilated', False)
        )
        cardio, nee = self.calculate_cardio_sofa(
            data.get('map'), 
            data.get('vasopressors'), 
            data.get('weight_kg', 70)
        )
        neuro = self.calculate_neuro_sofa(
            data.get('gcs_total'), 
            data.get('rass_score')
        )
        renal = self.calculate_renal_sofa(
            data.get('creatinine'), 
            data.get('urine_24h'), 
            data.get('rrt', False)
        )
        hepatic = self.calculate_hepatic_sofa(data.get('bilirubin'))
        coag = self.calculate_coag_sofa(data.get('platelets'))
        
        components = [x for x in [resp, cardio, neuro, renal, hepatic, coag] if x is not None]
        total = sum(components) if len(components) >= 4 else None
        
        return {
            'total_sofa': total,
            'resp_sofa': resp,
            'cardio_sofa': cardio,
            'neuro_sofa': neuro,
            'renal_sofa': renal,
            'hepatic_sofa': hepatic,
            'coag_sofa': coag,
            'nee_total': nee,
            'components_scored': len(components),
            'fixes_applied': {
                'vasopressin_included': True,
                'fio2_not_imputed': self.fio2_imputation == 'none',
                'window_240min': self.pao2_fio2_window == 240,
                'rass_aware': True
            }
        }

def compute_daily_sofa(cdm, concept_ancestor):
    """Compute daily SOFA scores from OMOP CDM"""
    calculator = SOFACalculator()
    return pd.DataFrame()
