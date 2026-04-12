"""
omop_utils.py v3.2 - Pragmatic edition
Implements hybrid concepts, tiered vasopressors, conditional FiO2, auditable assumptions
"""

import pandas as pd
import numpy as np
from config_pragmatic import *

VERBOSE = False
def set_verbose(v=True):
    global VERBOSE; VERBOSE = v
def _log(m):
    if VERBOSE: print(f"[utils] {m}")

# Hardcoded safety nets (top LOINCs by prevalence across 10 sites)
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
    'bilirubin': ['1975-2','1971-1'],
    'creatinine': ['2160-0','38483-4'],
    'platelets': ['777-3','778-1'],
    'pao2': ['2703-7','2019-8'],
    'fio2': ['19994-3','19995-0'],
    'spo2': ['2708-6','59408-5'],
    'map': ['8478-0'],
    'sbp': ['8480-6'],
    'dbp': ['8462-4'],
    'gcs_total': ['9269-2'],
    'gcs_eye': ['9267-6'],
    'gcs_verbal': ['9270-0'],
    'gcs_motor': ['9268-4'],
    'weight': ['29463-7'],
    'urine': ['3167-4']
}

def sql_concept_set(domain):
    codes = ",".join(f"'{c}'" for c in LOINC_CODES[domain])
    ancestor_sql = f"""SELECT ca.descendant_concept_id FROM {VOCAB_SCHEMA}.concept c
JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON c.concept_id=ca.ancestor_concept_id
WHERE c.vocabulary_id='LOINC' AND c.concept_code IN ({codes})"""
    if CONCEPT_MODE == "ancestor":
        return ancestor_sql
    elif CONCEPT_MODE == "hardcoded":
        ids = ",".join(map(str, HARDCODED[domain]))
        return f"SELECT unnest(ARRAY[{ids}])"
    else:  # hybrid
        ids = ",".join(map(str, HARDCODED[domain]))
        return f"{ancestor_sql} UNION SELECT unnest(ARRAY[{ids}])"

# Unit conversion via unit_concept_id
UNIT_MAP = {('bilirubin',8751):1/17.1, ('creatinine',8751):1/88.4, ('pao2',8870):7.50062, ('fio2',8554):0.01, ('spo2',8554):0.01}
def convert(val, domain, u):
    if pd.isna(val): return np.nan
    try: return float(val) * UNIT_MAP.get((domain,int(u)),1.0)
    except: return float(val)

def sql_vasopressors(person_ids=None):
    filt = f"AND de.person_id IN ({','.join(map(str,person_ids))})" if person_ids else ""
    return f"""
WITH v AS (
 SELECT de.person_id, de.visit_occurrence_id,
  COALESCE(de.drug_exposure_start_datetime,de.drug_exposure_start_date) AS start_time,
  COALESCE(de.drug_exposure_end_datetime,de.drug_exposure_end_date,COALESCE(de.drug_exposure_start_datetime,de.drug_exposure_start_date)+interval '1 hour') AS end_time,
  c.concept_id, c.concept_name, de.quantity, de.dose_unit_source_value,
  EXTRACT(EPOCH FROM (COALESCE(de.drug_exposure_end_datetime,de.drug_exposure_end_date)-COALESCE(de.drug_exposure_start_datetime,de.drug_exposure_start_date)))/60.0 AS dur,
  (SELECT value_as_number FROM {CLINICAL_SCHEMA}.measurement m WHERE m.person_id=de.person_id AND m.measurement_concept_id IN ({sql_concept_set('weight')})
   AND COALESCE(m.measurement_datetime,m.measurement_date)<=COALESCE(de.drug_exposure_start_datetime,de.drug_exposure_start_date)
   ORDER BY COALESCE(m.measurement_datetime,m.measurement_date) DESC LIMIT 1) AS wt
 FROM {CLINICAL_SCHEMA}.drug_exposure de
 JOIN {VOCAB_SCHEMA}.concept c ON de.drug_concept_id=c.concept_id
 JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id=ca.descendant_concept_id AND ca.ancestor_concept_id IN (1319998,1322081,1319997,1345852,1345853)
 WHERE de.route_concept_id=4171047 {filt}
)
SELECT *,
 CASE
   WHEN lower(dose_unit_source_value) LIKE '%mcg/kg/min%' THEN quantity
   WHEN lower(dose_unit_source_value) LIKE '%mcg/min%' THEN quantity/NULLIF(wt,0)
   WHEN dur>0 AND wt>0 THEN quantity*1000/dur/wt
   WHEN dur>0 THEN quantity*1000/dur/70.0
   ELSE NULL
 END AS rate,
 CASE
   WHEN lower(dose_unit_source_value) LIKE '%mcg/kg/min%' THEN 'direct'
   WHEN lower(dose_unit_source_value) LIKE '%mcg/min%' THEN 'weight_adjusted'
   WHEN dur>0 AND wt>0 THEN 'quantity_duration_weight'
   WHEN dur>0 THEN 'quantity_duration_70kg'
   ELSE 'unknown'
 END AS rate_source,
 CASE concept_id WHEN 1319998 THEN 1.0 WHEN 1322081 THEN 1.0 WHEN 1319997 THEN 0.01 WHEN 1345852 THEN 0.1 WHEN 1345853 THEN 2.5 ELSE 1.0 END AS norepi_factor
FROM v
"""

def sql_ventilation(pids=None):
    f = f"AND person_id IN ({','.join(map(str,pids))})" if pids else ""
    return f"SELECT person_id,visit_occurrence_id,COALESCE(procedure_datetime,procedure_date) AS s,COALESCE(procedure_end_datetime,COALESCE(procedure_datetime,procedure_date)+interval '1 hour') AS e FROM {CLINICAL_SCHEMA}.procedure_occurrence WHERE procedure_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id=4048778) {f}"

def sql_cultures(pids=None):
    f = f"AND person_id IN ({','.join(map(str,pids))})" if pids else ""
    return f"SELECT person_id,visit_occurrence_id,COALESCE(specimen_datetime,specimen_date) AS t FROM {CLINICAL_SCHEMA}.specimen WHERE specimen_concept_id IN (SELECT descendant_concept_id FROM {VOCAB_SCHEMA}.concept_ancestor WHERE ancestor_concept_id=4042031) {f}"

def sql_abx(pids=None):
    f = f"AND de.person_id IN ({','.join(map(str,pids))})" if pids else ""
    return f"SELECT de.person_id,de.visit_occurrence_id,COALESCE(de.drug_exposure_start_datetime,de.drug_exposure_start_date) AS t FROM {CLINICAL_SCHEMA}.drug_exposure de JOIN {VOCAB_SCHEMA}.concept_ancestor ca ON de.drug_concept_id=ca.descendant_concept_id WHERE ca.ancestor_concept_id=(SELECT concept_id FROM {VOCAB_SCHEMA}.concept WHERE vocabulary_id='ATC' AND concept_code='J01' LIMIT 1) AND de.route_concept_id=4171047 {f}"

def fetch(conn,sql): _log("exec"); return pd.read_sql(sql,conn)
