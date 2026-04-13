# OMOP SOFA & Sepsis-3 Calculator v4.5

Production implementation for OMOP CDM v5.4+. This release adds an enhanced pragmatic Sepsis-3 pipeline alongside the existing strict v4.4 pipeline.

## When to run which pipeline

Use the table below to choose. Both pipelines require `results_site_a.sofa_hourly` to exist first (run the standard SOFA calculation).

| Use Standard v4.4 (RUN_ALL.sql) | Use Enhanced v4.5 (RUN_ALL_enhanced.sql) |
| --- | --- |
| You need strict Sepsis-3 per Singer 2016 | You need pragmatic, real-world detection |
| Publication requires high specificity | You are doing ICU surveillance or quality improvement |
| You must have culture within 72h of antibiotics | Your site has variable culture timing (use 96h window) |
| You want 1:1 comparison to original validation cohorts | You want to avoid double-counting antibiotic courses |
| Regulatory or methods paper | Multi-center OMOP, MIMIC, N3C, CHoRUS, PCORnet |
| Accepts lower sensitivity (~2.7% prevalence at MGH) | Accepts higher sensitivity (~14.5% prevalence at MGH) |

**Rule of thumb:** run standard for the primary methods definition, run enhanced for the sensitivity analysis and for any operational dashboard. At MGH, the enhanced version matches clinical expectation.

## What changed in v4.5

1. **Infection definition expanded**
   - Standard: antibiotics + culture within 72h
   - Enhanced: culture within 96h OR ≥2 distinct antibiotics OR single antibiotic in ICU

2. **48-hour collapse**
   - Merges antibiotic starts <48h apart into one episode
   - Fixes the 11,364 raw rows → 5,225 collapsed episodes you saw

3. **ICU-onset filter**
   - Uses visit_detail ICU concepts to flag true ICU-onset sepsis

4. **30-day composite outcome**
   - death_30d from omopcdm.death
   - hospice_30d from visit_occurrence.discharged_to_concept_id
   - MGH uses concept 8546 = Hospice (not 38003568/9)

5. **Future date exclusion**
   - Drops infection_onset >= CURRENT_DATE (removes test data)

## Quick start

### Prerequisite (both pipelines)
```bash
# 1. Calculate hourly SOFA (v4.4)
python src/run_sofa_chunked.py --site site_a
# This creates results_site_a.sofa_hourly
```

### Option A: Standard v4.4
```bash
psql "postgresql://postgres:PASSWORD@host/mgh" -f sql/RUN_ALL.sql
# Creates: results_site_a.sepsis3_cases
```

### Option B: Enhanced v4.5 (recommended for MGH)
```bash
psql "postgresql://postgres:PASSWORD@host/mgh"   -v cdm_schema=omopcdm   -v vocab_schema=vocabulary   -v results_schema=results_site_a   -f sql/RUN_ALL_enhanced.sql
# Creates:
#  - view_infection_onset_enhanced
#  - sepsis3_enhanced
#  - sepsis3_enhanced_collapsed
#  - sepsis3_outcomes_30d
#  - sepsis3_summary
```

Download the enhanced script: RUN_ALL_enhanced_v4.5.sql

## MGH-specific configuration

Edit your site yaml or pass as psql variables:

```yaml
sepsis_enhanced:
  culture_window_hours: 96
  collapse_hours: 48
  hospice_concept_ids: [8546]  # MGH uses 8546
  use_discharged_to: true      # OMOP field is discharged_to_concept_id
```

Verify hospice codes at your site:
```sql
SELECT discharged_to_concept_id, concept_name, COUNT(*)
FROM omopcdm.visit_occurrence vo
JOIN vocabulary.concept c ON c.concept_id = vo.discharged_to_concept_id
WHERE discharged_to_concept_id IS NOT NULL
GROUP BY 1,2 ORDER BY 3 DESC LIMIT 10;
```

## Expected outputs (MGH validation 2026-04-13)

Run after enhanced pipeline:
```sql
SELECT * FROM results_site_a.sepsis3_summary;
```

| Metric | Value |
| --- | --- |
| icu_denominator | 7,277 |
| strict_patients | 196 |
| enhanced_patients | 1,052 |
| prevalence_pct | 14.5 |
| mean_delta_sofa | 3.6 |
| deaths_30d | 73 |
| hospice_30d | 14 |
| composite_30d | 77 |
| composite_pct | 7.3 |

Note: 30-day mortality is low because the CHoRUS death table is EHR-only and truncated. Report composite as "in-hospital death or hospice within 30 days" and note limitation.

## File inventory v4.5

```
sql/
  RUN_ALL.sql                      # standard v4.4
  RUN_ALL_enhanced.sql             # NEW v4.5
  23_view_infection_onset_enhanced.sql
  40_create_sepsis3_enhanced.sql
  41_create_sepsis3_collapsed_48h.sql
  42_create_sepsis3_outcomes_30d.sql
  43_create_sepsis3_summary.sql
```

## Methods text for manuscripts

**Standard:**
> Sepsis-3 was defined per Singer et al. as suspected infection (systemic antibiotics with blood culture within 72 hours) with an increase in SOFA score ≥2 points from baseline, where baseline was the lowest SOFA in the 24-72 hours preceding infection onset.

**Enhanced:**
> Pragmatic Sepsis-3 was defined as suspected infection (antibiotics with culture within 96 hours, ≥2 distinct antibiotics, or ICU antibiotic initiation) with ΔSOFA ≥2 within 48 hours. Antibiotic courses starting <48 hours apart were collapsed into a single episode. ICU-onset was determined from visit_detail. The primary outcome was 30-day all-cause mortality or discharge to hospice.

## Troubleshooting

**Low prevalence with standard:** expected. Standard requires culture, most sites miss 70% of cases.

**High episode count before collapse:** normal. Run the collapse table, check 48h logic.

**Hospice not counted:** confirm you use `discharged_to_concept_id` not `discharge_to_concept_id`, and your site's hospice concept (MGH 8546).

**Future dates:** enhanced view filters `infection_onset < CURRENT_DATE` automatically.

## Version history
- v4.4: strict Sepsis-3, 10 critical fixes
- v4.5: adds enhanced pragmatic pipeline, 48h collapse, 30d death/hospice, MGH hospice support
