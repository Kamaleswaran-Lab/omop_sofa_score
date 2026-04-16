# OMOP SOFA Score - MGH/CHoRUS Critical Fixes

This patch addresses three architectural time-bombs identified in the original repo:

## 1. 40_create_sepsis3_enhanced.sql - Community-Onset Erasure
- **Problem:** MIN(baseline_sofa) returned NULL for ED patients → HAVING dropped them
- **Fix:** COALESCE(...,0) per Sepsis-3 definition

## 2. 20_view_pao2_fio2_pairs.sql - Cartesian Explosion
- **Problem:** JOIN within 240min created 12-16 duplicates per PaO2
- **Fix:** ROW_NUMBER() to pick closest FiO2, 1:1 pairing

## 3. 30_view_sofa_components.sql - Timestamp Fragmentation
- **Problem:** FULL OUTER JOIN on exact timestamps created sparse rows, memory blowup
- **Fix:** date_trunc('hour') before joining

## Additional MGH-specific fixes included:
- **51_cdc_ase_blood_cultures.sql:** 40484543 is pressure ulcer in MGH vocab, replaced with 3023368 (Bacteria in Blood by Culture)
- **53_cdc_ase_organ_dysfunction.sql:** Replaced concept_ancestor with direct IDs, added COALESCE for datetime fields

Apply with:
psql ... -v results_schema=results_site_a -v cdm_schema=omopcdm -v vocab_schema=omopcdm -f 20_... -f 30_... -f 40_... etc.
