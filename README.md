# OMOP SOFA & Sepsis-3 v4.1 FULL

Complete pipeline for OMOP CDM v5.4+ that fixes all 10 fatal flaws in Kamaleswaran-Lab v3.5.

This is not a patch. It includes:
- 12 SQL views that compute each SOFA component from OMOP tables
- Antibiotic + culture detection for Sepsis-3 suspected infection
- Python chunked runner with connection pooling
- Full provenance logging (32 fields)
- Ancestor-only concept sets (no hardcoded LOINCs)

## Fixes implemented
1. Vasopressin INCLUDED via NEE 2.5x (was excluded)
2. FiO2: no 0.6/0.21 imputation, LOCF 6h only
3. PaO2/FiO2 window 240 min with nearest-neighbor
4. GCS: no verbal=1, RASS <= -4 => NULL, 24h pre-intubation carry
5. Baseline: pre-infection 72h min, not last_available
6. Renal: 24h rolling urine, RRT forces 4
7. Concepts: ancestor only
8. Units: explicit normalization
9. Ventilation: device + procedure + visit_detail
10. Provenance: full audit trail

See docs/VALIDATION_CHECKLIST.md
