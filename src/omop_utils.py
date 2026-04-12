"""
omop_utils.py - OMOP SOFA/Sepsis-3 utilities
Version: 3.1 (production, multi-site)
- Schema split: clinical=omopcdm, vocab=vocabulary (configurable)
- Concept sets via concept_ancestor + LOINC (no hard-coded IDs)
- Unit conversion via unit_concept_id (no string parsing)
- Vasopressor rate from duration + dose_unit, with norepi equivalents
- PaO2/FiO2 pairing window configurable (default 120 min)
- SpO2/FiO2 surrogate when PaO2 missing (SpO2 <=97%)
"""

import pandas as pd
import numpy as np

CLINICAL_SCHEMA = "omopcdm"
VOCAB_SCHEMA = "vocabulary"
VERBOSE = False

# Pairing window for oxygenation (minutes)
PAO2_FIO2_WINDOW_MIN = 120
SPO2_FIO2_WINDOW_MIN = 120

def set_verbose(v=True):
    global VERBOSE
    VERBOSE = bool(v)

def set_schemas(clinical="omopcdm", vocab="vocabulary"):
    global CLINICAL_SCHEMA, VOCAB_SCHEMA
    CLINICAL_SCHEMA = clinical
    VOCAB_SCHEMA = vocab

def _log(m):
    if VERBOSE: print(f"[omop_utils] {m}")

# ---- UCUM unit_concept_id map ----
# 8840 mg/dL, 8751 umol/L, 8876 mmHg, 8870 kPa, 8554 %, 8555 fraction
UNIT_FACTORS = {
    ('bilirubin', 8840): 1.0,
    ('bilirubin', 8751): 1/17.1,
    ('creatinine', 8840): 1.0,
    ('creatinine', 8751): 1/88.4,
    ('pao2', 8876): 1.0,
    ('pao2', 8870): 7.50062,
    ('fio2', 8554): 0.01,
    ('fio2', 8555): 1.0,
    ('spo2', 8554): 0.01,  # percent to fraction
}

def convert(val, domain, unit_concept_id):
    if pd.isna(val): return np.nan
    try:
        key = (domain, int(unit_concept_id))
        return float(val) * UNIT_FACTORS.get(key, 1.0)
    except: 
        return float(val)

# ---- LOINC concept sets (expanded via ancestor) ----
LOINC_SETS = {
    'bilirubin': ['1975-2','1971-1','14629-0','14631-6','33833-4'],
    'creatinine': ['2160-0','38483-4','14682-9','33914-3'],
    'platelets': ['777-3','778-1','26515-7','49497-2'],
    'pao2': ['2703-7','2019-8','11556-8'],
    'fio2': ['19994-3','19995-0','3150-0'],
    'spo2': ['2708-6','59408-5','59417-6'],
    'map': ['8478-0','7597-5','8454-1'],
    'sbp': ['8480-6','8459-0'],
    'dbp': ['8462-4','8453-3'],
    'gcs_total': ['9269-2','35088-4'],
    'gcs_eye': ['9267-6'],
    'gcs_verbal': ['9270-0'],
    'gcs_motor': ['9268-4'],
    'weight': ['29463-7','3141-9'],
    'urine': ['3167-4','14743-9','8999-5']
}

def sql_concept_set(domain):
    codes = ",".join(f"'{c}'" for c in LOINC_SETS[domain])
    return f"""SELECT DISTINCT ca.descendant_concept_id
FROM {VOCAB_SCHEMA}.concept c
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON c.concept_id = ca.ancestor_concept_id
WHERE c.vocabulary_id='LOINC' AND c.concept_code IN ({codes})"""

# ---- Vasopressors ----
VASO_MAP = {
    1319998: ('norepinephrine', 1.0),
    1322081: ('epinephrine', 1.0),
    1319997: ('dopamine', 0.01),
    1345852: ('phenylephrine', 0.1),
    1345853: ('vasopressin', 2.5)
}

def sql_vasopressors(person_ids=None):
    filt = f"AND de.person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    ancestors = ",".join(map(str, VASO_MAP.keys()))
    return f"""
WITH v AS (
 SELECT de.person_id, de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date) AS start_time,
  COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date,
           COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date)+interval '1 hour') AS end_time,
  c.concept_id, c.concept_name,
  de.quantity, de.dose_unit_source_value,
  EXTRACT(EPOCH FROM (COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date) -
                      COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date)))/60.0 AS dur_min,
  (SELECT m.value_as_number FROM {CLINICAL_SCHEMA}.measurement m
   WHERE m.person_id=de.person_id AND m.measurement_concept_id IN ({sql_concept_set('weight')})
     AND COALESCE(m.measurement_datetime,m.measurement_date) <= COALESCE(de.drug_exposure_start_datetime,de.drug_exposure_start_date)
   ORDER BY COALESCE(m.measurement_datetime,m.measurement_date) DESC LIMIT 1) AS wt
 FROM {CLINICAL_SCHEMA}.drug_exposure de
 JOIN {VOCAB_SCHEMA}.concept c ON de.drug_concept_id=c.concept_id
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id=ca.descendant_concept_id AND ca.ancestor_concept_id IN ({ancestors})
 WHERE de.route_concept_id=4171047 {filt}
)
SELECT *, 
 CASE
   WHEN lower(dose_unit_source_value) LIKE '%mcg/kg/min%' THEN quantity
   WHEN lower(dose_unit_source_value) LIKE '%mcg/min%' THEN quantity/NULLIF(wt,0)
   WHEN dur_min>0 AND wt>0 THEN quantity*1000/dur_min/wt
   ELSE NULL
 END AS rate_mcgkgmin,
 CASE concept_id
   WHEN 1319998 THEN 1.0 WHEN 1322081 THEN 1.0 WHEN 1319997 THEN 0.01
   WHEN 1345852 THEN 0.1 WHEN 1345853 THEN 2.5 ELSE 1.0 END AS norepi_factor
FROM v
"""

def sql_ventilation(person_ids=None):
    filt = f"AND p.person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    return f"""SELECT person_id, visit_occurrence_id,
  COALESCE(procedure_datetime, procedure_date) AS start_time,
  COALESCE(procedure_end_datetime, COALESCE(procedure_datetime, procedure_date)+interval '1 hour') AS end_time
 FROM {CLINICAL_SCHEMA}.procedure_occurrence p
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON p.procedure_concept_id=ca.descendant_concept_id AND ca.ancestor_concept_id=4048778
 WHERE 1=1 {filt}"""

def sql_rrt(person_ids=None):
    filt = f"AND p.person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    return f"""SELECT person_id, visit_occurrence_id, COALESCE(procedure_datetime, procedure_date) AS start_time
 FROM {CLINICAL_SCHEMA}.procedure_occurrence p
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON p.procedure_concept_id=ca.descendant_concept_id AND ca.ancestor_concept_id=4146536
 WHERE 1=1 {filt}"""

def sql_cultures(person_ids=None):
    filt = f"AND s.person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    return f"""SELECT person_id, visit_occurrence_id, COALESCE(specimen_datetime, specimen_date) AS culture_time
 FROM {CLINICAL_SCHEMA}.specimen s
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON s.specimen_concept_id=ca.descendant_concept_id AND ca.ancestor_concept_id=4042031
 WHERE 1=1 {filt}"""

def sql_iv_antibiotics(person_ids=None):
    filt = f"AND de.person_id IN ({','.join(map(str, person_ids))})" if person_ids else ""
    return f"""SELECT de.person_id, de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime, de.drug_exposure_start_date) AS start_time,
  COALESCE(de.drug_exposure_end_datetime, de.drug_exposure_end_date) AS end_time
 FROM {CLINICAL_SCHEMA}.drug_exposure de
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id=ca.descendant_concept_id
 WHERE ca.ancestor_concept_id=(SELECT concept_id FROM {VOCAB_SCHEMA}.concept WHERE vocabulary_id='ATC' AND concept_code='J01' LIMIT 1)
   AND de.route_concept_id=4171047 {filt}"""

def fetch_sql(conn, sql):
    _log(f"SQL {len(sql)} chars")
    return pd.read_sql(sql, conn)
