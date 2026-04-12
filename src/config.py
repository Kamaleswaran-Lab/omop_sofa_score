"""
config.py - Single source of truth for all configuration
Loads from config/{SITE}.yaml with environment variable substitution
"""

import yaml
import os
from pathlib import Path
import re

SITE = os.getenv('OMOP_SITE', 'template')
CONFIG_PATH = Path(__file__).parent.parent / 'config' / f'{SITE}.yaml'

def _substitute_env_vars(obj):
    """Replace ${VAR} with environment variables"""
    if isinstance(obj, dict):
        return {k: _substitute_env_vars(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [_substitute_env_vars(item) for item in obj]
    elif isinstance(obj, str):
        return re.sub(r'\$\{([^}]+)\}', lambda m: os.getenv(m.group(1), ''), obj)
    return obj

with open(CONFIG_PATH) as f:
    raw_config = yaml.safe_load(f)
    CONFIG = _substitute_env_vars(raw_config)

# Schemas
CLINICAL_SCHEMA = CONFIG['schemas']['clinical']
VOCAB_SCHEMA = CONFIG['schemas']['vocabulary']
RESULTS_SCHEMA = CONFIG['schemas'].get('results', CLINICAL_SCHEMA)

# Database
DB = CONFIG['database']

# Pragmatic settings
PRAGMATIC_MODE = CONFIG.get('pragmatic_mode', True)
CONCEPT_MODE = CONFIG.get('concept_mode', 'hybrid')
FIO2_IMPUTATION = CONFIG.get('fio2_imputation', 'conditional')
BASELINE_STRATEGY = CONFIG.get('baseline_strategy', 'last_available')
PAO2_FIO2_WINDOW = CONFIG.get('pao2_fio2_window', 120)
SPO2_FIO2_WINDOW = CONFIG.get('spo2_fio2_window', 120)
CHUNK_SIZE = CONFIG.get('chunk_size', 500)

# Data quality filters
DQ_FILTERS = CONFIG.get('data_quality', {
    'platelets_min': 5,
    'platelets_max': 2000,
    'creatinine_min': 0.1,
    'creatinine_max': 30,
    'bilirubin_max': 50,
    'fio2_min': 0.21,
    'fio2_max': 1.0
})

CODE_VERSION = "3.5"
