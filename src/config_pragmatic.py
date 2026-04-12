"""
config_pragmatic.py - Pragmatic mode for real-world EHR
Set PRAGMATIC_MODE=True for multi-site consortiums where ETL is incomplete.
All heuristics are logged to sofa_assumptions table for TTE sensitivity analysis.
"""

PRAGMATIC_MODE = True

# 1. Concept expansion: "hybrid" uses ancestor + hardcoded safety net
CONCEPT_MODE = "hybrid"  # options: "ancestor", "hardcoded", "hybrid"

# 2. Vasopressor rate fallback chain
VASO_RATE_STRATEGY = "tiered"  # tries dose_unit, then quantity/duration/weight, then quantity/duration/70kg

# 3. FiO2 imputation
FIO2_IMPUTATION = "conditional"  # "none", "conditional", "aggressive_21"
# conditional = vent -> carry forward else 0.6, non-vent + no O2 -> 0.21

# 4. Baseline SOFA
BASELINE_STRATEGY = "last_available"  # "min_72_6", "last_available", "zero"
# last_available = try min -72 to -6, else last -24 to -1, else 0 with flag

# Pairing windows (minutes)
PAO2_FIO2_WINDOW = 120
SPO2_FIO2_WINDOW = 120

# Schemas
CLINICAL_SCHEMA = "omopcdm"
VOCAB_SCHEMA = "vocabulary"
