# OMOP Sepsis Phenotyping Pipeline

PostgreSQL implementation of Sepsis-3 (SOFA) and CDC Adult Sepsis Event (ASE)
phenotypes for OMOP CDM v5.4.

The canonical SQL path is `sql/RUN_ALL_enhanced.sql`. Older runners are retained
only as deprecated compatibility stubs.

## Run Order

```bash
export PGPASSWORD='your_password'
export DB='postgresql://user@host/omop?sslmode=require'

psql "$DB" \
  -v ON_ERROR_STOP=1 \
  -v results_schema=results \
  -v cdm_schema=omopcdm \
  -v vocab_schema=vocabulary \
  -f sql/RUN_ALL_enhanced.sql
```

The runner builds:

| Object | Purpose |
| --- | --- |
| `concept_set_members` | Canonical ATHENA/local concept-set registry |
| `concept_set_validation_failures` | Fail-fast vocabulary validation output |
| `view_infection_onset` | Antibiotic/culture candidate infection events |
| `sofa_hourly` | Event-scoped hourly SOFA component and total scores |
| `sepsis3_cohort` | Sepsis-3 cases with `sofa_delta >= 2` |
| `cdc_ase_cohort_final` | CDC ASE cohort with outcomes/support flags |
| `sepsis_cohort_comparison` | Matched Sepsis-3 vs CDC ASE comparison |

## Concept And Vocabulary Policy

Concepts are managed in `sql/03_create_concept_sets.sql`.

- ATHENA vocabulary concepts are validated for existence, invalid status,
  expected domain when applicable, and standard concept status.
- Site-local concept IDs are allowed only when explicitly marked
  `local_allowed = true`.
- Antibiotics are expanded from the antibacterial ancestor `21602796` into
  standard Drug-domain descendants.
- Vasopressors, ventilation, urine output, renal replacement therapy, PaO2,
  FiO2, cultures, labs, vitals, and GCS use named concept sets.

If validation fails, inspect:

```sql
SELECT *
FROM results.concept_set_validation_failures
ORDER BY concept_set_name, concept_id;
```

## Scale Notes

- `sofa_hourly` is built from infection-onset windows, not from each patient's
  full first-to-last measurement span.
- Hot joins use `(concept_id, person_id, datetime)` and `(person_id, hr)` indexes.
- `RUN_ALL_enhanced.sql` does not mutate SQL files at runtime.
- The SOFA table exposes a stable contract: `hr`, component scores,
  `total_sofa`, and `components_observed`.

## Validation

Run static SQL checks before database execution:

```bash
bash validate/static_sql_checks.sh
```

Then run the pipeline with `ON_ERROR_STOP=1` and review final row counts:

```sql
SELECT 'sepsis3' AS cohort, COUNT(*) FROM results.sepsis3_cohort
UNION ALL
SELECT 'cdc_ase', COUNT(*) FROM results.cdc_ase_cohort_final
UNION ALL
SELECT cohort_type, COUNT(*) FROM results.sepsis_cohort_comparison GROUP BY cohort_type;
```

For live scale validation, collect `EXPLAIN (ANALYZE, BUFFERS)` on
`31_create_sofa_hourly.sql`, `40_create_sepsis3_enhanced.sql`, and
`61_create_sepsis_cohort_comparison.sql` using representative production data.
