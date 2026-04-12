"""
omop_utils.py - MGH CHoRUS SQL backend (v2, triple-checked)
Replaces flat-file DataFrame loading with direct PostgreSQL queries.
All original functionalities preserved: concept_ancestor expansion, unit conversion,
COALESCE datetime handling, schema split (omopcdm + vocabulary).
"""

import pandas as pd
import numpy as np

CLINICAL_SCHEMA = "omopcdm"
VOCAB_SCHEMA = "vocabulary"
VERBOSE = False

def set_verbose(v=True):
    global VERBOSE
    VERBOSE = bool(v)

def set_schemas(clinical="omopcdm", vocab="vocabulary"):
    global CLINICAL_SCHEMA, VOCAB_SCHEMA
    CLINICAL_SCHEMA = clinical
    VOCAB_SCHEMA = vocab

def _log(msg):
    if VERBOSE:
        print(f"[omop_utils] {msg}")

# ---- Validated concept sets (README) ----
BILIRUBIN_IDS = [3024128, 3005673, 3037290, 3010156, 3049077]
CREATININE_IDS = [3016723, 3020564, 3006155, 3022068]
PLATELETS_IDS = [3024929, 3007461, 3013682, 3024980, 3039193]
PAO2_IDS = [3012731, 3024561, 3006277]
FIO2_IDS = [3016502, 3023541, 3020718, 3035196]
MAP_IDS = [3019962, 3034703]
SBP_IDS = [3004249, 3018586]
DBP_IDS = [3019960, 3013940]
GCS_TOTAL_IDS = [3005823]
GCS_EYE_IDS = [3009097]
GCS_VERBAL_IDS = [3008223]
GCS_MOTOR_IDS = [3016517]
WEIGHT_IDS = [3025315]
URINE_OUTPUT_IDS = [3004304, 4021485]

VASOPRESSOR_ANCESTORS = [1319998, 1322081, 1319997, 1345852, 1345853]
VENTILATION_ANCESTOR = 4048778
RRT_ANCESTOR = 4146536
CULTURE_ANCESTOR = 4042031

# ---- Unit conversions ----
def to_mg_dl_bilirubin(val, unit):
    if pd.isna(val): return np.nan
    if unit and 'umol' in str(unit).lower():
        return float(val) / 17.1
    return float(val)

def to_mg_dl_creatinine(val, unit):
    if pd.isna(val): return np.nan
    if unit and 'umol' in str(unit).lower():
        return float(val) / 88.4
    return float(val)

def to_mmhg_pao2(val, unit):
    if pd.isna(val): return np.nan
    if unit and 'kpa' in str(unit).lower():
        return float(val) * 7.50062
    return float(val)

def to_fraction_fio2(val, unit):
    if pd.isna(val): return np.nan
    v = float(val)
    return v / 100.0 if v > 1.5 else v

def to_k_per_ul_platelets(val, unit):
    if pd.isna(val): return np.nan
    return float(val)

def _in_clause(ids):
    return ",".join(str(int(i)) for i in ids)

# ---- SQL generators ----
def sql_iv_antibiotics(person_ids=None, start_date='2019-01-01'):
    filt = ""
    if person_ids is not None:
        ids = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND de.person_id IN ({ids})"
    return f"""
SELECT
  de.person_id,
  de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_time,
  COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date::timestamp,
           COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) + INTERVAL '1 hour') AS end_time,
  c.concept_id AS drug_concept_id,
  c.concept_name AS drug_name,
  de.quantity,
  de.dose_unit_source_value,
  de.route_concept_id
FROM {CLINICAL_SCHEMA}.drug_exposure de
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id = ca.descendant_concept_id
JOIN {VOCAB_SCHEMA}.concept c ON de.drug_concept_id = c.concept_id
WHERE ca.ancestor_concept_id = (
    SELECT concept_id FROM {VOCAB_SCHEMA}.concept
    WHERE vocabulary_id='ATC' AND concept_code='J01' AND invalid_reason IS NULL LIMIT 1
)
  AND de.route_concept_id = 4171047
  AND COALESCE(de.drug_exposure_start_date, '1900-01-01') >= DATE '{start_date}'
  {filt}
"""

def sql_measurements(concept_ids, person_ids=None):
    ids = _in_clause(concept_ids)
    filt = ""
    if person_ids is not None:
        pid = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND m.person_id IN ({pid})"
    return f"""
SELECT
  m.person_id,
  m.visit_occurrence_id,
  COALESCE(m.measurement_datetime, m.measurement_date::timestamp) AS meas_time,
  m.measurement_concept_id,
  c.concept_name,
  m.value_as_number,
  m.unit_concept_id,
  u.concept_name AS unit_name,
  m.unit_source_value
FROM {CLINICAL_SCHEMA}.measurement m
JOIN {VOCAB_SCHEMA}.concept c ON m.measurement_concept_id = c.concept_id
LEFT JOIN {VOCAB_SCHEMA}.concept u ON m.unit_concept_id = u.concept_id
WHERE m.measurement_concept_id IN ({ids}) {filt}
"""

def sql_vasopressors(person_ids=None):
    filt = ""
    if person_ids is not None:
        pid = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND de.person_id IN ({pid})"
    ancestors = _in_clause(VASOPRESSOR_ANCESTORS)
    return f"""
SELECT
  de.person_id,
  de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp) AS start_time,
  COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date::timestamp) AS end_time,
  de.drug_concept_id,
  c.concept_name AS drug_name,
  de.quantity,
  de.dose_unit_source_value,
  w.weight_kg
FROM {CLINICAL_SCHEMA}.drug_exposure de
JOIN {VOCAB_SCHEMA}.concept c ON de.drug_concept_id = c.concept_id
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id = ca.descendant_concept_id AND ca.ancestor_concept_id IN ({ancestors})
LEFT JOIN LATERAL (
  SELECT m.value_as_number AS weight_kg
  FROM {CLINICAL_SCHEMA}.measurement m
  WHERE m.person_id = de.person_id
    AND m.measurement_concept_id = 3025315
    AND COALESCE(m.measurement_datetime, m.measurement_date::timestamp) <= COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date::timestamp)
  ORDER BY COALESCE(m.measurement_datetime, m.measurement_date::timestamp) DESC LIMIT 1
) w ON true
WHERE de.route_concept_id = 4171047 {filt}
"""

def sql_ventilation(person_ids=None):
    filt = ""
    if person_ids is not None:
        pid = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND p.person_id IN ({pid})"
    return f"""
SELECT
  p.person_id,
  p.visit_occurrence_id,
  COALESCE(p.procedure_datetime, p.procedure_date::timestamp) AS start_time,
  COALESCE(p.procedure_end_datetime, COALESCE(p.procedure_datetime, p.procedure_date::timestamp) + INTERVAL '1 hour') AS end_time
FROM {CLINICAL_SCHEMA}.procedure_occurrence p
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON p.procedure_concept_id = ca.descendant_concept_id AND ca.ancestor_concept_id = {VENTILATION_ANCESTOR}
WHERE 1=1 {filt}
"""

def sql_rrt(person_ids=None):
    filt = ""
    if person_ids is not None:
        pid = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND p.person_id IN ({pid})"
    return f"""
SELECT
  p.person_id,
  p.visit_occurrence_id,
  COALESCE(p.procedure_datetime, p.procedure_date::timestamp) AS start_time
FROM {CLINICAL_SCHEMA}.procedure_occurrence p
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON p.procedure_concept_id = ca.descendant_concept_id AND ca.ancestor_concept_id = {RRT_ANCESTOR}
WHERE 1=1 {filt}
"""

def sql_cultures(person_ids=None):
    filt = ""
    if person_ids is not None:
        pid = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND s.person_id IN ({pid})"
    return f"""
SELECT person_id, visit_occurrence_id,
       COALESCE(specimen_datetime, specimen_date::timestamp) AS culture_time
FROM {CLINICAL_SCHEMA}.specimen s
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON s.specimen_concept_id = ca.descendant_concept_id AND ca.ancestor_concept_id = {CULTURE_ANCESTOR}
WHERE 1=1 {filt}
"""

def sql_urine_output(person_ids=None):
    ids = _in_clause(URINE_OUTPUT_IDS)
    filt = ""
    if person_ids is not None:
        pid = _in_clause(person_ids if isinstance(person_ids, (list, tuple, set)) else [person_ids])
        filt = f" AND m.person_id IN ({pid})"
    return f"""
SELECT
  m.person_id,
  m.visit_occurrence_id,
  COALESCE(m.measurement_datetime, m.measurement_date::timestamp) AS meas_time,
  m.value_as_number AS urine_ml
FROM {CLINICAL_SCHEMA}.measurement m
WHERE m.measurement_concept_id IN ({ids}) {filt}
"""

def fetch_sql(conn, sql):
    _log(f"SQL exec")
    return pd.read_sql(sql, conn)
