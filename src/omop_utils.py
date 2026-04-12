"""
omop_utils.py v3.5 - Production ready
"""

import pandas as pd
import numpy as np
from config import CLINICAL_SCHEMA, VOCAB_SCHEMA, CONCEPT_MODE, DQ_FILTERS
import psycopg2
from psycopg2 import pool

# Connection pool
_connection_pool = None

def get_connection_pool():
    global _connection_pool
    if _connection_pool is None:
        from config import DB
        _connection_pool = psycopg2.pool.SimpleConnectionPool(1, 10, **DB)
    return _connection_pool

def get_connection():
    return get_connection_pool().getconn()

def return_connection(conn):
    get_connection_pool().putconn(conn)

VERBOSE = False
def set_verbose(v=True): 
    global VERBOSE
    VERBOSE = v

def _log(m):
    if VERBOSE:
        print(f"[utils] {m}")

HARDCODED = {
    'bilirubin': [3024128,3005673,3037290,3010156,3049077],
    'creatinine': [3016723,3020564,3006155,3022068],
    'platelets': [3024929,3007461,3013682,3024980,3039193],
    'pao2': [3012731,3024561,3006277],
    'fio2': [3016502,3023541,3020718,3035196],
    'spo2': [3016503,3027018,40762434],
    'map': [3019962,3034703],
    'sbp': [3004249,3018586],
    'dbp': [3019960,3013940],
    'gcs_total': [3005823],
    'gcs_eye': [3009097],
    'gcs_verbal': [3008223],
    'gcs_motor': [3016517],
    'weight': [3025315],
    'urine': [3004304,4021485]
}

LOINC_CODES = {
    'bilirubin': ['1975-2','1971-1'], 'creatinine': ['2160-0','38483-4'],
    'platelets': ['777-3','778-1'], 'pao2': ['2703-7','2019-8'],
    'fio2': ['19994-3','19995-0'], 'spo2': ['2708-6','59408-5'],
    'map': ['8478-0'], 'sbp': ['8480-6'], 'dbp': ['8462-4'],
    'gcs_total': ['9269-2'], 'gcs_eye': ['9267-6'], 'gcs_verbal': ['9270-0'], 'gcs_motor': ['9268-4'],
    'weight': ['29463-7'], 'urine': ['3167-4']
}

def sql_concept_set(d):
    codes = ",".join(f"'{c}'" for c in LOINC_CODES[d])
    anc = f"SELECT ca.descendant_concept_id FROM {VOCAB_SCHEMA}.concept c JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON c.concept_id=ca.ancestor_concept_id WHERE c.vocabulary_id='LOINC' AND c.concept_code IN ({codes})"
    if CONCEPT_MODE == "ancestor":
        return anc
    if CONCEPT_MODE == "hardcoded":
        return f"SELECT unnest(ARRAY[{','.join(map(str, HARDCODED[d]))}])"
    return f"{anc} UNION SELECT unnest(ARRAY[{','.join(map(str, HARDCODED[d]))}])"

UNIT_MAP = {
    ('bilirubin', 8751): 1/17.1,
    ('creatinine', 8751): 1/88.4,
    ('pao2', 8870): 7.50062,
    ('fio2', 8554): 0.01,
    ('spo2', 8554): 0.01,
    ('urine', 8587): 1000,  # L to mL
    ('urine', 8739): 1,     # mL
}

def convert(v, dom, u):
    if pd.isna(v):
        return np.nan
    try:
        return float(v) * UNIT_MAP.get((dom, int(u)), 1.0)
    except:
        return float(v)

def apply_dq_filters(df):
    """Apply data quality filters"""
    if 'plt_v' in df.columns:
        df = df[(df['plt_v'].isna()) | ((df['plt_v'] >= DQ_FILTERS['platelets_min']) & (df['plt_v'] <= DQ_FILTERS['platelets_max']))]
    if 'creat' in df.columns:
        df = df[(df['creat'].isna()) | ((df['creat'] >= DQ_FILTERS['creatinine_min']) & (df['creat'] <= DQ_FILTERS['creatinine_max']))]
    if 'bili' in df.columns:
        df = df[(df['bili'].isna()) | (df['bili'] <= DQ_FILTERS['bilirubin_max'])]
    if 'fio2' in df.columns:
        df = df[(df['fio2'].isna()) | ((df['fio2'] >= DQ_FILTERS['fio2_min']) & (df['fio2'] <= DQ_FILTERS['fio2_max']))]
    return df

def sql_vasopressors(pids=None):
    f = f"AND de.person_id IN ({','.join(map(str, pids))})" if pids else ""
    return f"""
WITH v AS (
 SELECT de.person_id, de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date) AS s,
  COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date, COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date) + interval '1 hour') AS e,
  c.concept_id, c.concept_name, de.quantity, de.dose_unit_source_value,
  EXTRACT(EPOCH FROM (COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date) - COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date)))/60.0 AS dur,
  (SELECT value_as_number FROM {CLINICAL_SCHEMA}.measurement m WHERE m.person_id=de.person_id AND m.measurement_concept_id IN ({sql_concept_set('weight')}) AND COALESCE(m.measurement_datetime, m.measurement_date) <= COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date) ORDER BY COALESCE(m.measurement_datetime, m.measurement_date) DESC LIMIT 1) AS wt
 FROM {CLINICAL_SCHEMA}.drug_exposure de
 JOIN {VOCAB_SCHEMA}.concept c ON de.drug_concept_id = c.concept_id
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id = ca.descendant_concept_id AND ca.ancestor_concept_id IN (1319998, 1322081, 1319997, 1345852, 1345853)
 WHERE de.route_concept_id = 4171047 {f}
)
SELECT *,
 CASE
   WHEN concept_id = 1345853 THEN NULL  -- vasopressin handled separately
   WHEN lower(dose_unit_source_value) LIKE '%mcg/kg/min%' THEN quantity
   WHEN lower(dose_unit_source_value) LIKE '%mcg/min%' THEN quantity / NULLIF(wt, 0)
   WHEN dur > 0 AND wt > 0 THEN quantity * 1000 / dur / wt
   WHEN dur > 0 THEN quantity * 1000 / dur / 70.0
   ELSE NULL
 END AS rate,
 CASE
   WHEN concept_id = 1345853 THEN 'vasopressin_units'
   WHEN lower(dose_unit_source_value) LIKE '%mcg/kg/min%' THEN 'direct'
   WHEN lower(dose_unit_source_value) LIKE '%mcg/min%' THEN 'weight_adjusted'
   WHEN dur > 0 AND wt > 0 THEN 'quantity_duration_weight'
   WHEN dur > 0 THEN 'quantity_duration_70kg'
   ELSE 'unknown'
 END AS rate_source,
 CASE concept_id
   WHEN 1319998 THEN 1.0 WHEN 1322081 THEN 1.0 WHEN 1319997 THEN 0.01
   WHEN 1345852 THEN 0.1 WHEN 1345853 THEN 2.5 ELSE 1.0
 END AS norepi_factor
FROM v
"""

def sql_ventilation(pids=None):
    f = f"AND person_id IN ({','.join(map(str, pids))})" if pids else ""
    return f"""
SELECT person_id, visit_occurrence_id, COALESCE(procedure_datetime, procedure_date) AS s,
       COALESCE(procedure_end_datetime, COALESCE(procedure_datetime, procedure_date) + interval '24 hours') AS e
FROM {CLINICAL_SCHEMA}.procedure_occurrence
WHERE procedure_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id = 4048778) {f}
UNION ALL
SELECT person_id, visit_occurrence_id, device_exposure_start_datetime AS s,
       COALESCE(device_exposure_end_datetime, device_exposure_start_datetime + interval '24 hours') AS e
FROM {CLINICAL_SCHEMA}.device_exposure
WHERE device_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id = 45768192) {f}
"""

def sql_map_derived(pids=None):
    f = f"AND m.person_id IN ({','.join(map(str, pids))})" if pids else ""
    return f"""
WITH map_direct AS (
  SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS map
  FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('map')}) {f}
),
sbp AS (
  SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS sbp
  FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('sbp')}) {f}
),
dbp AS (
  SELECT person_id, visit_occurrence_id, COALESCE(measurement_datetime, measurement_date) AS ts, value_as_number AS dbp
  FROM {CLINICAL_SCHEMA}.measurement WHERE measurement_concept_id IN ({sql_concept_set('dbp')}) {f}
)
SELECT COALESCE(m.person_id, s.person_id, d.person_id) AS person_id,
       COALESCE(m.visit_occurrence_id, s.visit_occurrence_id, d.visit_occurrence_id) AS visit_occurrence_id,
       COALESCE(m.ts, s.ts, d.ts) AS ts,
       COALESCE(m.map, (s.sbp + 2*d.dbp)/3) AS map,
       CASE WHEN m.map IS NOT NULL THEN 'direct' ELSE 'derived' END AS map_source
FROM map_direct m
FULL OUTER JOIN sbp s ON m.person_id = s.person_id AND m.visit_occurrence_id = s.visit_occurrence_id AND abs(extract(epoch FROM m.ts - s.ts)) < 300
FULL OUTER JOIN dbp d ON COALESCE(m.person_id, s.person_id) = d.person_id AND COALESCE(m.visit_occurrence_id, s.visit_occurrence_id) = d.visit_occurrence_id AND abs(extract(epoch FROM COALESCE(m.ts, s.ts) - d.ts)) < 300
"""

def sql_chronic_flags(pids=None):
    f = f"AND person_id IN ({','.join(map(str, pids))})" if pids else ""
    return f"""
SELECT person_id,
 MAX(CASE WHEN condition_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id = 4030518) THEN 1 ELSE 0 END) AS esrd,
 MAX(CASE WHEN condition_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id = 4245975) THEN 1 ELSE 0 END) AS cirrhosis,
 MAX(CASE WHEN condition_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id = 317576) THEN 1 ELSE 0 END) AS heart_failure
FROM {CLINICAL_SCHEMA}.condition_occurrence WHERE 1=1 {f} GROUP BY person_id
"""

def fetch(conn, sql):
    _log(f"Executing SQL ({len(sql)} chars)")
    return pd.read_sql(sql, conn)
