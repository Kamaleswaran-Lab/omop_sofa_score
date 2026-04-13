# OMOP SOFA & Sepsis-3 Calculator v4.4
## Site A Validated Implementation

Production-ready SOFA and Sepsis-3 for OHDSI OMOP CDM v5.4+

### Site A Validation Results (2026-04-12)

| Component | Concept ID | Records | Status |
|-----------|------------|---------|--------|
| Creatinine | 3016723 | 549,112 | OK |
| Bilirubin | 3024128 | 239,317 | OK |
| Platelets | 3024929 | 489,315 | OK (was 7,974 with old ID) |
| Lactate | 3047181+3014111 | 145,613 | OK (was 0) |
| PaO2 | 3027315 | 7,974 | OK (was 0) |
| FiO2 | 4353936 | 1,495,269 | OK |

### 10 Critical Fixes in v4.4

1. **Vasopressin included** at 2.5x NEE (was excluded)
2. **No FiO2 imputation** (was 0.6/0.21)
3. **240-min PaO2/FiO2 window** (was 120)
4. **RASS-aware GCS nulling** (RASS <= -4 -> NULL)
5. **Pre-infection 72h baseline** (was last_available)
6. **24h rolling urine sum** (was hourly snapshot)
7. **Ancestor concepts only** (not hardcoded)
8. **Explicit unit conversion**
9. **3-domain ventilation detection**
10. **32-field provenance audit**

### Quick Start

```bash
# 1. Configure
cp config/site_template.yaml config/site_a.yaml
# Edit database connection details

export OMOP_SITE=site_a
export SITE_A_DB_PASSWORD="your_password"

# 2. Validate concepts
python src/validate_concepts.py   --connection-string "postgresql://postgres:${SITE_A_DB_PASSWORD}@host/db"   --cdm-schema omopcdm   --vocab-schema vocabulary

# 3. Initialize database
psql -d your_db -f sql/00_create_schemas.sql
psql -d your_db -f sql/01_create_assumptions_table.sql
psql -d your_db -f sql/02_create_indexes.sql

# 4. Create views (all 16 SQL files)
for sql in sql/*.sql; do psql -d your_db -f "$sql"; done

# 5. Run pipeline
python src/run_sofa_chunked.py --site site_a
```

### Output Tables

- `results_site_a.sofa_hourly` - Hourly SOFA scores
- `results_site_a.sepsis3_cases` - Sepsis-3 incident cases
- `results_site_a.sofa_assumptions` - 32-field audit trail
