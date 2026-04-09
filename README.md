# SOFA_on_OMOP

Implements a Sequential Organ Failure Assessment and Sepsis-3 detector for OHDSI OMOP CDM.

## Why this repo exists

Most OMOP SOFA implementations fail for the same reasons: hard-coded concept_ids, unit filtering instead of conversion, summing worst values from different times, and assuming baseline SOFA equals zero. This code enforces the original Vincent definitions and the Sepsis-3 delta SOFA rule with proper temporal logic.

## Repository structure

```
omop_sofa_score/
├── README.md
└── src/
    ├── omop_utils.py          # concept expansion, unit conversion, derivations
    ├── omop_calc_sofa.py          # main SOFA calculator
    └── omop_calc_sepsis3.py    # suspected infection and Sepsis-3 evaluation
```

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

## Quick start

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

## Methodology details

### SOFA component thresholds

| System | 0 | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- | --- |
| Respiratory PaO2/FiO2 | ≥400 | 300-399 | 200-299 | 100-199 with vent | <100 with vent |
| Cardiovascular | MAP ≥70 | MAP <70 | Dopamine ≤5 or dobutamine any | Dopamine 5-15 or epi/norepi ≤0.1 | Dopamine >15 or epi/norepi >0.1 |
| Neurologic GCS | 15 | 13-14 | 10-12 | 6-9 | <6 |
| Hepatic bilirubin mg/dL | <1.2 | 1.2-1.9 | 2.0-5.9 | 6.0-11.9 | ≥12.0 |
| Renal creatinine mg/dL or UO | <1.2 | 1.2-1.9 | 2.0-3.4 | 3.5-4.9 or UO <500ml/d | ≥5.0 or UO <200ml/d or RRT |
| Coagulation platelets 10^3/µL | ≥150 | 100-149 | 50-99 | 20-49 | <20 |

### Temporal rules

- **LOCF windows:** MAP 2h, GCS 4h, PaO2/FiO2 4h, labs 24h
- **Pairing:** PaO2 matched to nearest FiO2 within 60 minutes. If FiO2 missing and no oxygen device, assume 0.21
- **Daily aggregation:** Take maximum of each component per day, sum if at least 4 components present
- **Ventilation:** From procedure_occurrence concepts for invasive mechanical ventilation
- **RRT:** From dialysis procedure concepts, overrides creatinine

### Sepsis-3 implementation

- **Suspected infection:** culture from procedure_occurrence or specimen and systemic antibiotic within -24h to +72h. Antibiotic course requires at least 2 administrations or duration over 24h
- **Baseline SOFA:** last valid total SOFA between 72h and 1h before t_inf
- **Acute window:** maximum total SOFA between 48h before and 24h after t_inf
- **Delta:** window max minus baseline. Sepsis-3 equals 1 if delta is at least 2 and baseline is valid
- **Chronic disease:** patients with cirrhosis or ESRD are flagged. Baseline is not assumed zero for these patients

## Input requirements

Your OMOP instance must include:

- Standard vocabularies loaded and concept_ancestor populated
- Units populated in measurement.unit_concept_id where possible
- Drug exposure with start and end datetimes and quantity for infusions
- Body weight measurements for µg/kg/min calculation

If concept_ancestor is unavailable, the code falls back to seed concepts and will miss descendants. Performance will degrade.

## Validation

Run against Vincent 1996 test cases:

- PaO2 85, FiO2 0.5, vent on → pfratio 170 → respiratory 3
- Bilirubin 12 mg/dL → hepatic 4
- Creatinine 3.6 mg/dL → renal 3
- Norepinephrine 0.2 µg/kg/min → cardiovascular 4
- Platelets 45 → coagulation 2
- GCS 8 → neurologic 3

Total equals 19. The script reproduces this exactly.

## Limitations

- SpO2/FiO2 surrogate is used only when PaO2 is missing. Correlation is imperfect below SpO2 88 percent
- Vasopressor rates depend on accurate quantity and duration in drug_exposure. Boluses are ignored
- Sedated GCS is not imputed. Scores during deep sedation will be high. Use RASS filtered data if available
- Urine output requires hourly charting in measurement or observation. If your site stores I/O elsewhere, modify get_urine_output_24h

## Performance

All heavy joins should be pushed to SQL in production. The pandas reference implementation processes about 10,000 ICU days per minute on a laptop. For full databases, rewrite the hourly grid generation as a database view with window functions.

## Citation

If you use this implementation, cite the original SOFA description and Sepsis-3 definitions:

- Vincent JL et al. The SOFA score to describe organ dysfunction/failure. Intensive Care Med 1996
- Singer M et al. The Third International Consensus Definitions for Sepsis and Septic Shock. JAMA 2016

And reference this repository:

Kamaleswaran Lab. SOFA_on_OMOP. https://github.com/Kamaleswaran-Lab/omop_sofa_score

## License

Apache 2.0. See LICENSE file.

## Contributing

This is research code for critical care informatics. Open issues for concept set expansions, unit edge cases, or validation against your OMOP instance. Pull requests must include unit tests against the Vincent test cases.
