
# OMOP SOFA & Sepsis-3 Calculator v4.0 COMPLETE

Production-ready rewrite addressing all v3.5 fatal flaws for multi-site OMOP CDM v5.4+ (MIMIC-IV, N3C, Duke, MGH).

## What changed from v3.5
- Vasopressin INCLUDED via NEE 2.5x (was excluded)
- FiO2: NO hardcoded 0.6/0.21, uses LOCF 6h
- PaO2/FiO2 window: 240 min (was 120)
- GCS: no verbal=1, RASS-aware nulling + 24h pre-intubation carry
- Baseline: pre_infection_72h min (was last_available)
- Renal: rolling 24h urine, RRT detection forces score 4
- Concepts: ancestor-only, zero hardcoded LOINCs
- Ventilation: device_exposure + procedure_occurrence + visit_detail
- Provenance: 32-field sofa_assumptions table

Pragmatic mode defaults to FALSE for scientific use.
