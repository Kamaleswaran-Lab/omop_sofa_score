# SOFA_on_OMOP

Implements a correct, portable Sequential Organ Failure Assessment and Sepsis-3 detector for OHDSI OMOP CDM. Fixes the informatics errors that make most public SOFA scripts non-reproducible across sites.

## Why this repo exists

Most OMOP SOFA implementations fail for the same reasons: hard-coded concept_ids, unit filtering instead of conversion, summing worst values from different times, and assuming baseline SOFA equals zero. This code enforces the original Vincent definitions and the Sepsis-3 delta SOFA rule with proper temporal logic.

## Repository structure
omop_sofa_score/
├── README.md
├── omop_calc_sofa.py # main SOFA calculator
└── src/
├── omop_utils.py # concept expansion, unit conversion, derivations
└── omop_calc_sepsis3.py # suspected infection and Sepsis-3 evaluation


## What is different

- **Concept sets, not IDs.** All domains expand via `concept_ancestor`. Works on any OMOP v5.4+ database.
- **Units converted, not dropped.** Creatinine µmol/L to mg/dL, bilirubin µmol/L to mg/dL, PaO2 kPa to mmHg, FiO2 percent to fraction, platelets 10^9/L to 10^3/µL.
- **Hourly SOFA, then daily worst.** Each organ system scored at the same hour using last observation carried forward, then max per calendar day. No Frankenstein scores.
- **Physiology correct.** PaO2/FiO2 paired within 60 minutes, ventilation status required for respiratory 3-4, vasopressors converted to norepinephrine equivalents in µg/kg/min, MAP derived from SBP/DBP when needed, GCS summed from components, urine output summed to 24h, RRT forces renal 4.
- **Sepsis-3 baseline fixed.** Baseline is last SOFA in -72h to -1h, not max before -48h. Baseline is never assumed zero for patients with chronic organ dysfunction.

## Installation

Python 3.9 or higher required.

```bash
pip install pandas numpy
```

Load your CDM into a dictionary of DataFrames:

```python
cdm = {
    'person': person_df,
    'visit_occurrence': visit_df,
    'measurement': measurement_df,
    'drug_exposure': drug_df,
    'procedure_occurrence': procedure_df,
    'condition_occurrence': condition_df,
    'specimen': specimen_df,
    'concept_ancestor': concept_ancestor_df
}
```

```python
from omop_calc_sofa import compute_daily_sofa
from src.omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

# 1. Daily SOFA
daily_sofa = compute_daily_sofa(cdm, cdm['concept_ancestor'])

# returns: person_id, visit_occurrence_id, chartdate, total_sofa,
# resp_sofa, cardio_sofa, neuro_sofa, hepatic_sofa, renal_sofa, coag_sofa

# 2. Suspected infection
suspected = compute_suspected_infection(cdm, cdm['concept_ancestor'])

# 3. Sepsis-3
sepsis3 = evaluate_sepsis3(daily_sofa, suspected, cdm, cdm['concept_ancestor'])
```

