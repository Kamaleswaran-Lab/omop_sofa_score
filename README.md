# OMOP Sepsis Phenotyping Pipeline

PostgreSQL implementation of Sepsis-3 (SOFA) and Adult Sepsis Event (ASE) phenotypes on OMOP CDM v5.4.

Based on Kamaleswaran et al. with modifications for 72-hour infection window and IV-only antibiotics.

## Build Order

Run SQL files in order against your OMOP database:

```bash
export PGPASSWORD='your_password'
export DB="postgresql://postgres@your-host/mgh?sslmode=require"

# 1. Core assumptions and vocab
psql $DB -f sql/00_assumptions.sql

# 2. Cultures view
psql $DB -f sql/22_view_cultures.sql

# 3. Infection onset (72h window)
psql $DB -f sql/23_view_infection_onset.sql

# 4. SOFA components
psql $DB -f sql/30_view_sofa_components.sql
psql $DB -f sql/31_view_sofa_score.sql

# 5. Sepsis-3 cohort
psql $DB -f sql/40_create_sepsis3.sql

# 6. ASE phenotype
psql $DB -f sql/50_view_antibiotics.sql
psql $DB -f sql/51_view_blood_cultures.sql
psql $DB -f sql/52_create_ase.sql

# 7. Validation tables
psql $DB -f sql/60_validation.sql
```

## Key Assumptions

### 1. Assumptions Table
`results_site_a.assumptions` serves dual purpose:
- **Parameters**: window sizes, thresholds
- **Concept lists**: antibiotic concept_ids

| domain | parameter | value | description |
|--------|-----------|-------|-------------|
| antibiotic | window_hours | 72 | Hours between culture and antibiotic |
| culture | lookback_hours | 48 | Lookback for cultures |
| sofa | baseline_window | 24 | Hours before infection for baseline |
| sofa | delta_threshold | 2 | SOFA increase for Sepsis-3 |
| ase | qad_days | 4 | Qualified antibiotic days |
| ase | organ_window | 7 | Days for organ dysfunction |

Plus ~2,800 antibiotic concept_ids loaded from:
```sql
SELECT descendant_concept_id 
FROM vocabulary.concept_ancestor 
WHERE ancestor_concept_id = 21602796 -- Antibacterial agent
```

### 2. Infection Onset Definition
**72-hour window** (expanded from standard 48h):
- Antibiotic start: first IV antibiotic (route_concept_id = 4112421)
- Culture time: specimen_datetime from view_cultures
- Pairing: ABS(abx - culture) <= 72 hours
- Onset: LEAST(abx_start, culture_time)

Rationale: captures delayed cultures in real-world EHR data.

### 3. Cultures
view_cultures sources from OMOP specimen and measurement tables:
- Blood, respiratory, urine, sterile site cultures
- Uses specimen_datetime as event time
- No visit_occurrence_id linkage (joined via person_id only)

### 4. Antibiotics
- Route restriction: IV only (4112421)
- Concept source: full antibacterial hierarchy
- Excludes oral, topical, prophylactic doses

### 5. SOFA Score
- Baseline: lowest SOFA in 24h pre-infection
- Components calculated hourly
- Missing data: carried forward 24h, then assumed normal
- Sepsis-3: ΔSOFA ≥2 within infection window

### 6. ASE Definition
- QAD: ≥4 consecutive days of antibiotics (allowing 1-day gap)
- Blood culture: within ±2 days of antibiotic start
- Organ dysfunction: any SOFA component ≥2 within 7 days

## Schema Requirements

- omopcdm.* - OMOP CDM v5.4 tables
- vocabulary.* - Standard vocabularies
- results_site_a.* - Output schema (configurable via search_path)

Required OMOP tables:
- drug_exposure
- measurement
- specimen
- visit_occurrence
- concept_ancestor

## Output Tables

| Table | Description |
|-------|-------------|
| view_infection_onset | Paired antibiotic-culture events |
| view_sofa_components | Hourly SOFA organ scores |
| sepsis3_cohort | Sepsis-3 cases (ΔSOFA≥2) |
| ase_cohort | Adult Sepsis Events |

## Validation

Run after build:
```sql
SELECT * FROM results_site_a.validation_summary;
```

Expected at site:
- Infection onsets: ~18,000
- Sepsis-3: ~12,000
- ASE: ~8,500
- Overlap: ~65%

## Customization

Edit 00_assumptions.sql to change:
- Window hours (48 vs 72)
- IV-only vs all routes
- SOFA baseline method
