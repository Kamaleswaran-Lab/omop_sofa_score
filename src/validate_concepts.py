#!/usr/bin/env python3
import argparse, psycopg2, pandas as pd
from chorus_concepts import *

def validate(conn_str, cdm_schema, vocab_schema):
    conn = psycopg2.connect(conn_str)
    print("="*70)
    print("OMOP SOFA Concept Validation - Site A")
    print("="*70)
    
    checks = [
        ("PaO2", PAO2_CONCEPTS[0], 7974),
        ("FiO2", FIO2_CONCEPTS[0], 1495269),
        ("Creatinine", CREATININE_CONCEPTS[0], 549112),
        ("Bilirubin", BILIRUBIN_CONCEPTS[0], 239317),
        ("Platelets", PLATELETS_CONCEPTS[0], 489315),
        ("Lactate", LACTATE_CONCEPTS[0], 78297),
    ]
    
    for name, cid, expected in checks:
        df = pd.read_sql(f"SELECT COUNT(*) as n FROM {cdm_schema}.measurement WHERE measurement_concept_id={cid}", conn)
        actual = df.iloc[0]['n']
        status = "OK" if abs(actual-expected)/expected < 0.1 else "WARN"
        print(f"[{status}] {name:12} {cid:>9} | expected {expected:>9,} | actual {actual:>9,}")
    
    conn.close()

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--connection-string", required=True)
    p.add_argument("--cdm-schema", default="omopcdm")
    p.add_argument("--vocab-schema", default="vocabulary")
    a = p.parse_args()
    validate(a.connection_string, a.cdm_schema, a.vocab_schema)
