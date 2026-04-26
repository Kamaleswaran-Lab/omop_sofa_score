#!/bin/bash
# CHORUS Sepsis-3 Pipeline Validation Script v2.2
# REQUIRES connection string as argument 1
# Usage:./validate_sepsis_pipeline.sh "postgresql://user:pass@host/db?sslmode=require" [schema]

if [ $# -lt 1 ]; then
  echo "ERROR: Connection string required"
  echo ""
  echo "Usage:"
  echo " $0 \"postgresql://postgres:PASS@host/mgh?sslmode=require\" [schema_name]"
  echo ""
  echo "Example:"
  echo " $0 \"postgresql://postgres:%29kwe26b-m9x%5D27SX@psql-chorus-main.postgres.database.azure.com/mgh?sslmode=require\" results_site_a"
  exit 1
fi

CONN="$1"
SCHEMA="${2:-results_site_a}"
OUTFILE="sepsis_validation_$(date +%Y%m%d_%H%M%S).log"

echo "=== CHORUS Sepsis-3 Validation ===" | tee $OUTFILE
echo "Started: $(date)" | tee -a $OUTFILE
echo "Schema: $SCHEMA" | tee -a $OUTFILE
echo "" | tee -a $OUTFILE

run_query() {
    echo "----------------------------------------" | tee -a $OUTFILE
    echo "$1" | tee -a $OUTFILE
    echo "----------------------------------------" | tee -a $OUTFILE
    psql "$CONN" -v ON_ERROR_STOP=0 -c "$2" 2>&1 | tee -a $OUTFILE
    echo "" | tee -a $OUTFILE
}

LABS_VIEW=$(psql "$CONN" -tAc "SELECT table_name FROM information_schema.views WHERE table_schema='$SCHEMA' AND table_name LIKE 'view_labs%' ORDER BY table_name LIMIT 1;")
VITALS_VIEW=$(psql "$CONN" -tAc "SELECT table_name FROM information_schema.views WHERE table_schema='$SCHEMA' AND table_name LIKE 'view_vitals%' ORDER BY table_name LIMIT 1;")

echo "Detected: LABS_VIEW=$LABS_VIEW, VITALS_VIEW=$VITALS_VIEW" | tee -a $OUTFILE
echo "" | tee -a $OUTFILE

run_query "0a. PaO2 concepts" "
SELECT concept_id, concept_name, COUNT(m.*) as measurements
FROM vocabulary.concept c
LEFT JOIN omopcdm.measurement m ON m.measurement_concept_id = c.concept_id
WHERE domain_id='Measurement' AND concept_name ILIKE 'oxygen [partial pressure] in arterial blood%'
GROUP BY 1,2 ORDER BY 3 DESC;"

run_query "0b. FiO2 concepts" "
SELECT concept_id, concept_name,
       (SELECT COUNT(*) FROM omopcdm.measurement WHERE measurement_concept_id = c.concept_id) as meas,
       (SELECT COUNT(*) FROM omopcdm.observation WHERE observation_concept_id = c.concept_id) as obs
FROM vocabulary.concept c
WHERE (concept_name ILIKE '%fraction of inspired oxygen%' OR concept_name ILIKE 'fio2%' OR concept_name ILIKE '%inspired oxygen%')
ORDER BY (meas+obs) DESC NULLS LAST LIMIT 20;"

run_query "0c. Where is FiO2 actually stored?" "
SELECT measurement_concept_id, c.concept_name, COUNT(*), MIN(value_as_number), MAX(value_as_number)
FROM omopcdm.measurement m
JOIN vocabulary.concept c ON c.concept_id = m.measurement_concept_id
WHERE value_as_number BETWEEN 21 AND 100
  AND (c.concept_name ILIKE '%oxygen%' OR c.concept_name ILIKE '%fio2%')
GROUP BY 1,2 HAVING COUNT(*) > 1000
ORDER BY 3 DESC LIMIT 15;"

run_query "0d. Culture concepts" "
SELECT c.concept_id, c.concept_name, COUNT(m.*) as n
FROM vocabulary.concept c
JOIN omopcdm.measurement m ON m.measurement_concept_id = c.concept_id
WHERE c.concept_name ILIKE '%culture%' AND c.domain_id='Measurement'
GROUP BY 1,2 HAVING COUNT(*)>100 ORDER BY 3 DESC LIMIT 20;"

run_query "1. Core Data Counts" "
SELECT '${LABS_VIEW}' as src, COUNT(*) FROM ${SCHEMA}.${LABS_VIEW}
UNION ALL SELECT '${VITALS_VIEW}', COUNT(*) FROM ${SCHEMA}.${VITALS_VIEW}
UNION ALL SELECT 'cultures', COUNT(*) FROM ${SCHEMA}.view_cultures
UNION ALL SELECT 'pao2_fio2', COUNT(*) FROM ${SCHEMA}.view_pao2_fio2_pairs
UNION ALL SELECT 'abx_patients', COUNT(DISTINCT person_id) FROM ${SCHEMA}.view_antibiotics;"

run_query "2. Cultures Breakdown" "
SELECT c.concept_name, COUNT(*) AS n
FROM ${SCHEMA}.view_cultures vc
JOIN vocabulary.concept c ON c.concept_id = vc.source_concept_id
GROUP BY 1 ORDER BY n DESC LIMIT 15;"

run_query "3. Antibiotics Timing" "
SELECT COUNT(*) AS total_abx,
       MIN(drug_exposure_start_datetime) AS earliest,
       MAX(drug_exposure_start_datetime) AS latest
FROM ${SCHEMA}.view_antibiotics;"

run_query "4. PaO2/FiO2 Validation" "
SELECT COUNT(*) AS pairs,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pf_ratio)::numeric,1) AS median_pf
FROM ${SCHEMA}.view_pao2_fio2_pairs;"

run_query "5. Labs Coverage" "
SELECT COALESCE(lab_name, measurement_concept_id::text) as lab, COUNT(*)
FROM ${SCHEMA}.${LABS_VIEW}
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;"

run_query "6. Vitals Coverage" "
SELECT COALESCE(vital_name, measurement_concept_id::text) as vital, COUNT(*)
FROM ${SCHEMA}.${VITALS_VIEW}
GROUP BY 1 ORDER BY 2 DESC LIMIT 20;"

echo "=== Complete: $(date) ===" | tee -a $OUTFILE
