# OMOP SOFA & Sepsis-3 Calculator - v3.5 Production

**Production-ready implementation for multi-site critical care research**

Implements Sequential Organ Failure Assessment (SOFA) and Sepsis-3 criteria on OHDSI OMOP CDM v5.4+. Designed for high-fidelity target trial emulations, adaptive platform trials, and multi-center consortiums.

## Version 3.5 - All Critical Fixes Applied

This release addresses 20 gaps identified in production review:

**Clinical Correctness:**
- MAP derived from SBP/DBP when direct MAP missing (+23% availability)
- Urine output unit conversion (L to mL)
- Ventilation detection from device_exposure (+65% vent hours)
- GCS handling for intubated patients (assumes verbal=1T)
- Vasopressin excluded from rate calculations (units differ)
- Visit-based hourly grid (not lab-dependent)
- Data quality filters (platelets, creatinine, bilirubin, FiO2)

**Multi-Site Architecture:**
- Single YAML config per site (no hardcoded connections)
- Environment variable secrets
- Configurable schemas per site
- Connection pooling
- Results schema separation

**Audit & Reproducibility:**
- Complete sofa_assumptions table (15 fields)
- Code version tracking
- All imputations logged
- Chronic disease flags for baseline

## Quick Start

### 1. Configure Your Site

```bash
git clone https://github.com/Kamaleswaran-Lab/omop_sofa_score
cd omop_sofa_score
pip install -r requirements.txt

# Copy template
cp config/site_template.yaml config/mycenter.yaml

# Edit config/mycenter.yaml
```

Example config/duke.yaml:
```yaml
site_name: "Duke University"
schemas:
  clinical: "cdm_duke"
  vocabulary: "vocab"
  results: "results_duke"
database:
  dbname: "duke_omop"
  user: "researcher"
  host: "duke-db.edu"
  password: "${DUKE_DB_PASSWORD}"
  port: 5432
pragmatic_mode: true
concept_mode: "hybrid"
```

### 2. Set Environment

```bash
export OMOP_SITE=duke
export DUKE_DB_PASSWORD="your_password"
```

### 3. Initialize Database

```bash
psql -d duke_omop -f sql/create_assumptions_table.sql
psql -d duke_omop -f sql/create_indexes.sql
```

### 4. Validate Site

```bash
python src/validate_concepts.py
```

### 5. Run SOFA Calculation

```bash
python src/run_sofa_chunked.py
```

## Configuration Reference

| Key | Description | Default |
|-----|-------------|---------|
| schemas.clinical | OMOP CDM schema | omopcdm |
| schemas.vocabulary | Vocabulary schema | vocabulary |
| pragmatic_mode | Enable real-world heuristics | true |
| concept_mode | ancestor, hardcoded, or hybrid | hybrid |
| fio2_imputation | none or conditional | conditional |
| baseline_strategy | min_72_6 or last_available | last_available |
| pao2_fio2_window | Pairing window (minutes) | 120 |
| chunk_size | Patients per batch | 500 |

## Pragmatic Mode

When pragmatic_mode is true:

1. **Hybrid Concepts**: Queries both concept_ancestor AND hardcoded LOINCs
2. **Tiered Vasopressors**: Four-tier fallback for rate calculation
3. **Conditional FiO2**: Vent=0.6, non-vent=0.21 when missing
4. **Last-Available Baseline**: Uses most recent SOFA if 72h window empty

## Output Tables

**sofa_hourly**: Hourly SOFA scores
- person_id, visit_occurrence_id, charttime
- total, resp, cardio, neuro, hepatic, renal, coag (0-4 each)
- pf, sf_eq, ne, ne_src, mv, mv_src
- fio2_imp_method, vent, code_version

**sofa_assumptions**: Audit log of all imputations

## Performance

MGH CHoRUS (713 GB, 50k ICU stays):
- With indexes: 3 min per 500-patient chunk
- Without indexes: >2 hours per chunk
- Memory: <2 GB per chunk

## Files

```
config/
  site_template.yaml
  mgh.yaml, duke.yaml, stanford.yaml
src/
  config.py, omop_utils.py, omop_calc_sofa.py
  omop_calc_sepsis3.py, validate_concepts.py
  run_sofa_chunked.py
sql/
  create_assumptions_table.sql, create_indexes.sql
```

## License

Apache 2.0
