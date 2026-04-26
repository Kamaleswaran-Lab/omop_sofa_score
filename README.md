# OMOP SOFA Score v4.5-fixed (Duke Validation – April 2026)

**This is a fully Athena-validated rebuild of the Kamaleswaran Lab OMOP SOFA pipeline.** All concept IDs have been triple-checked against a live OMOP vocabulary (Duke instance). Previous AI-generated hallucinations have been removed.

## Critical Fixes Applied

### Concept ID Corrections (verified)
| Wrong ID (removed) | What it actually was | Correct Replacement |
|-------------------|---------------------|---------------------|
| 3013290 | CO₂ partial pressure | **Removed** – platelets now 3024929, 3016682 only |
| 3020714 | Acetaldehyde | FiO₂ now **3024882, 3020716** |
| 40484543 | Pressure ulcer | Cultures now **618898,1447635,3516065,3667301,3667306** |
| 40486635 | Valve prolapse | (see above) |
| 4052531 | Portal cannula | RRT now uses dialysis ancestor lookup |
| 4254663 | Lymphocyte count | GCS now uses LOINC codes 9267-6,9268-4,9266-8,9269-2 |
| 4254664 | Lipid crystalline | (see above) |
| 2072499989 | B2AI non-standard ICU | ICU now **32037, 581379** only |

### Pipeline Changes
1. **10_view_labs_core.sql** – platelets and lactate arrays corrected
2. **11_view_vitals_core.sql** – removed >2B local concepts
3. **14_view_neuro.sql** – GCS pulled by LOINC, not SNOMED hallucinations
4. **15_view_urine_24h.sql** – uses LOINC 3014315
5. **20_view_pao2_fio2_pairs.sql** – PaO₂/FiO₂ now mathematically valid
6. **22_view_cultures.sql** – true blood culture specimens
7. **RUN_ALL_enhanced_v4.5.sql** – **removed WHERE icu_onset=1** to enable full inpatient trajectories for MedGemma 1 reward shaping and delirium modeling

### Why ICU filter was removed
The original pipeline restricted to ICU onset, which truncated pre-ICU antibiotic exposure and post-ICU outcomes. For offline RL and optimal ICU drug management in elderly delirium, complete hospital trajectories are required.

## Usage (Duke Kubernetes)
```bash
psql "host=... dbname=ohdsi" -v cdm_schema=omopcdm -v vocab_schema=vocabulary -v results_schema=results_site_a -f sql/RUN_ALL_enhanced.sql
```

## Validation
Run the included concept check:
```sql
SELECT concept_id, concept_name FROM vocabulary.concept WHERE concept_id IN (...);
```
All IDs in this release return expected clinical meanings.

## Files
- sql/00-43: core SOFA, enhanced Sepsis-3, CDC ASE stubs
- All views use :cdm_schema, :vocab_schema, :results_schema variables – no hardcoding

Generated 2026-04-25 after Athena validation.
