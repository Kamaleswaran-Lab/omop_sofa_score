# OMOP SOFA & Sepsis-3 Calculator - v3.1 Production

Implements Sequential Organ Failure Assessment and Sepsis-3 on OHDSI OMOP CDM v5.4+

Designed for high-fidelity critical care research, multi-site consortiums, and target trial emulations. Replaces flat-file processing with direct PostgreSQL execution.

## Critical Fixes in v3.1

1. **Vasopressor rate, not quantity** - computes ug/kg/min from duration and weight; norepinephrine equivalents applied correctly
2. **No aggressive FiO2=0.21** - PaO2/FiO2 paired within 120 min (configurable), no imputation
3. **SpO2/FiO2 surrogate added** - used when PaO2 missing and SpO2 <=97%, converted to PF equivalent via Rice equation
4. **Concept sets, not IDs** - all labs expanded via concept_ancestor + LOINC codes
5. **Unit conversion via unit_concept_id** - UCUM standard, no string parsing
6. **GCS components summed** - falls back to Eye+Verbal+Motor when total missing
7. **Baseline SOFA corrected** - uses min in -72h to -6h, not last value at -1h
8. **SQL-native temporal logic** - hourly grid and LOCF via window functions, no pandas loops

## Installation

```bash
pip install pandas numpy psycopg2-binary
git clone https://github.com/Kamaleswaran-Lab/omop_sofa_score
cd omop_sofa_score
```

## Quick Start (MGH CHoRUS)

```python
import psycopg2
from src.omop_utils import set_schemas, set_verbose
from src.omop_calc_sofa import compute_hourly_sofa, compute_daily_sofa
from src.omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

set_schemas(clinical="omopcdm", vocab="vocabulary")
set_verbose(True)

conn = psycopg2.connect(dbname="mgh", user="postgres", host="...", password="...")

# Hourly SOFA with 120-min oxygenation window
hourly = compute_hourly_sofa(conn, person_ids=[1907])
daily = compute_daily_sofa(conn, person_ids=[1907])

# Sepsis-3
suspected = compute_suspected_infection(conn, person_ids=[1907])
sepsis3 = evaluate_sepsis3(hourly, suspected)
```

## Configuration for Multi-Site

```python
from src import omop_utils as u
u.PAO2_FIO2_WINDOW_MIN = 120  # default, increase to 240 for manual charting
u.SPO2_FIO2_WINDOW_MIN = 120
```

## Oxygenation Logic

- **PaO2/FiO2**: paired within 120 min, LOCF 4h, no imputation
- **SpO2/FiO2**: used when PaO2 missing AND SpO2 <=97%, paired within 120 min, converted to PF equivalent: PF = (SF*100 - 64) / 0.84 (Rice 2007)
- **Ventilation**: required for respiratory SOFA 3-4, from procedure_occurrence (concept_ancestor 4048778)

## Validation

Run Vincent 1996 test case:
- PaO2 85, FiO2 0.5, vent -> PF 170 -> resp 3
- Bilirubin 12 mg/dL -> hepatic 4
- Creatinine 3.6 -> renal 3
- Norepi 0.2 ug/kg/min -> cardio 4
- Platelets 45 -> coag 3
- GCS 8 -> neuro 3
Total = 20

## Files

- `src/omop_utils.py` - schema, concepts, units, vasopressors
- `src/omop_calc_sofa.py` - hourly/daily SOFA
- `src/omop_calc_sepsis3.py` - suspected infection, Sepsis-3
- `tests/test_vincent.py` - validation cases

## Citation

Vincent JL et al. Intensive Care Med 1996; Singer M et al. JAMA 2016
