#!/usr/bin/env python3
import argparse
import psycopg2
import pandas as pd
from chorus_concepts import (
    PAO2_CONCEPTS, FIO2_CONCEPTS, CREATININE_CONCEPTS,
    BILIRUBIN_CONCEPTS, PLATELETS_CONCEPTS, LACTATE_CONCEPTS
)

def validate(conn_str, cdm_schema):
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
        query = f"SELECT COUNT(*) as n FROM {cdm_schema}.measurement WHERE measurement_concept_id = {cid}"
        df = pd.read_sql(query, conn)
        actual = df.iloc[0]['n']
        status = "OK" if abs(actual - expected) / expected < 0.1 else "WARN"
        print(f"[{status}] {name:12} {cid:>9} | expected {expected:>9,} | actual {actual:>9,}")
    
    conn.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--cdm-schema", default="omopcdm")
    args = parser.parse_args()
    validate(args.connection_string, args.cdm_schema)
