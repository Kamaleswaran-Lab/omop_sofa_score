# OMOP SOFA & Sepsis-3 Calculator v4.4
## Site A Validated Implementation

Production-ready SOFA and Sepsis-3 for OHDSI OMOP CDM v5.4+

### Site A Validation (2026-04-12)
- Creatinine (3016723): 549,112 records
- Bilirubin (3024128): 239,317 records  
- Platelets (3024929): 489,315 records
- Lactate (3047181+3014111): 145,613 records
- PaO2 (3027315): 7,974 records
- FiO2 (4353936): 1,495,269 records

### 10 Critical Fixes
1. Vasopressin included at 2.5x
2. No FiO2 imputation
3. 240-min PaO2/FiO2 window
4. RASS-aware GCS nulling
5. Pre-infection 72h baseline
6. 24h rolling urine
7. Ancestor concepts
8. Unit conversion
9. 3-domain ventilation
10. 32-field audit log

### Quick Start
```bash
python src/validate_concepts.py --connection-string "postgresql://..."
python src/run_sofa_chunked.py --site site_a
```
