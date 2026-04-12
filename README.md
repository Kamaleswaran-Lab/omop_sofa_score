# OMOP SOFA & Sepsis-3 Calculator - v3.2 Pragmatic

Production version for real-world EHR, multi-site consortiums, and target trial emulations.

## Pragmatic Mode (default ON)

This version implements the survival heuristics required when ETL is incomplete:

1. **Hybrid concepts** - UNION of concept_ancestor + hardcoded top LOINCs
2. **Tiered vasopressors** - dose_unit -> quantity/duration/weight -> quantity/duration/70kg -> flag
3. **Conditional FiO2** - vent: carry-forward else 0.6; non-vent no O2: 0.21
4. **Last-available baseline** - min -72 to -6, else last -24 to -1, else 0 with flag

All assumptions logged for sensitivity analysis.

## Installation

```bash
pip install pandas numpy psycopg2-binary
```

## Quick Start

```python
import psycopg2
from src.config_pragmatic import PRAGMATIC_MODE
from src.omop_calc_sofa import compute_hourly_sofa

conn = psycopg2.connect(dbname="mgh", user="postgres")
hourly = compute_hourly_sofa(conn, person_ids=[1907])
# Check assumptions
hourly[['charttime','ne','ne_src']].head()
```

## Toggle Strict Mode

Edit src/config_pragmatic.py:
```python
PRAGMATIC_MODE = False
CONCEPT_MODE = "ancestor"
FIO2_IMPUTATION = "none"
BASELINE_STRATEGY = "min_72_6"
```
