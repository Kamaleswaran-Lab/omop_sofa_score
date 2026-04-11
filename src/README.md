# SOFA_on_OMOP

Implements Sequential Organ Failure Assessment and Sepsis-3 detector for OHDSI OMOP CDM.

## Critical Fixes Applied

This version corrects fatal concept ID errors found in original implementations:

1. **Bilirubin**: Removed 3013721 (was AST, not bilirubin)
2. **Creatinine**: Removed 3013682 (was platelets, not creatinine)
3. **All labs**: Expanded concept sets with validated LOINC codes
4. **Temporal logic**: Hourly SOFA grid preserves timing, no noon assumption
5. **All infections**: Evaluates all infection episodes, not just first
6. **Vasopressors**: Unit-aware calculation with proper end-time imputation

## Installation

```bash
pip install pandas numpy
```

## Usage

```python
from src.omop_utils import set_verbose
from src.omop_calc_sofa import compute_daily_sofa, compute_hourly_sofa
from src.omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

set_verbose(True)

# Compute SOFA (hourly for accuracy, daily for reporting)
hourly_sofa = compute_hourly_sofa(cdm, ancestor_df)
daily_sofa = compute_daily_sofa(cdm, ancestor_df)

# Find infections
suspected = compute_suspected_infection(cdm, ancestor_df)

# Evaluate Sepsis-3
sepsis3 = evaluate_sepsis3(hourly_sofa, suspected, cdm, ancestor_df)
```

## Validated Concept IDs

Based on OHDSI MIMIC, Vanderbilt BioVU, and EHDEN:

- **Bilirubin**: 3024128, 3005673, 3037290, 3010156, 3049077
- **Creatinine**: 3016723, 3020564, 3006155, 3022068
- **Platelets**: 3024929, 3007461, 3013682, 3024980, 3039193
- **PaO2**: 3012731, 3024561, 3006277
- **FiO2**: 3016502, 3023541, 3020718, 3035196

## Citation

Vincent JL et al. Intensive Care Med 1996; Singer M et al. JAMA 2016
