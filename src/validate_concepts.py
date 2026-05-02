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
    print("OMOP SOFA Concept Validation")
    print("="*70)
    
    checks = [
        ("PaO2", PAO2_CONCEPTS),
        ("FiO2", FIO2_CONCEPTS),
        ("Creatinine", CREATININE_CONCEPTS),
        ("Bilirubin", BILIRUBIN_CONCEPTS),
        ("Platelets", PLATELETS_CONCEPTS),
        ("Lactate", LACTATE_CONCEPTS),
    ]
    
    for name, concept_ids in checks:
        ids = ",".join(str(cid) for cid in concept_ids)
        query = f"SELECT COUNT(*) as n FROM {cdm_schema}.measurement WHERE measurement_concept_id IN ({ids})"
        df = pd.read_sql(query, conn)
        actual = df.iloc[0]['n']
        status = "OK" if actual > 0 else "WARN"
        print(f"[{status}] {name:12} concepts={len(concept_ids):>2} | actual {actual:>9,}")
    
    conn.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--connection-string", required=True)
    parser.add_argument("--cdm-schema", default="omopcdm")
    args = parser.parse_args()
    validate(args.connection_string, args.cdm_schema)
