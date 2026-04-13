# OMOP SOFA & Sepsis-3 Calculator v4.4
## Site A Validated Implementation

**Production-ready SOFA and Sepsis-3 for OHDSI OMOP CDM v5.4+**

This fork includes Site A validated concept mappings.

### Site A Validation Results (2026-04-12)
| Component | Concept ID | Records | Status |
|-----------|------------|---------|--------|
| Creatinine | 3016723 | 549,112 | â |
| Bilirubin | 3024128 | 239,317 | â |
| Platelets | 3024929 | 489,315 | â (was 7,974) |
| Lactate | 3047181+3014111 | 145,613 | â (was 0) |
| PaO2 | 3027315 | 7,974 | â (was 0) |
| FiO2 | 4353936 | 1,495,269 | â |
| SpO2 | 2147483345 | 11,885,033 | â |
| Temperature | 3020891 | 13,155,082 | â |

### 10 Critical Fixes in v4.4
1. **Vasopressin included** (2.5x NEE) - was excluded
2. **No FiO2 imputation** - eliminates false respiratory failure
3. **240-min PaO2/FiO2 window** - was 120 min
4. **RASS-aware GCS nulling** - distinguishes sedation
5. **Pre-infection 72h baseline** - correct Sepsis-3 delta
6. **24h rolling urine** - proper renal SOFA
7. **Ancestor concepts** - portable
8. **Unit conversion** - explicit
9. **3-domain ventilation** - +65% detection
10. **32-field audit log** - full provenance

### Quick Start

```bash
# Clone and setup
git clone https://github.com/Kamaleswaran-Lab/omop_sofa_score
cd omop_sofa_score

# Configure Site A
cp config/site_template.yaml config/site_a.yaml
# Edit database connection

export OMOP_SITE=site_a
export SITE_A_DB_PASSWORD="..."

# Validate concepts
python src/validate_concepts.py   --connection-string "postgresql://postgres:${SITE_A_DB_PASSWORD}@host/db"   --cdm-schema omopcdm   --vocab-schema vocabulary

# Initialize database
psql -d your_db -f sql/00_create_schemas.sql
psql -d your_db -f sql/01_create_assumptions_table.sql
psql -d your_db -f sql/02_create_indexes.sql

# Run full pipeline
python src/run_sofa_chunked.py --site site_a
```

### Output Tables
- `results_site_a.sofa_hourly` - hourly SOFA scores
- `results_site_a.sepsis3_cases` - Sepsis-3 incidents
- `results_site_a.sofa_assumptions` - 32-field audit trail

### Citation
Kamaleswaran Lab. OMOP SOFA v4.4. https://github.com/Kamaleswaran-Lab/omop_sofa_score
