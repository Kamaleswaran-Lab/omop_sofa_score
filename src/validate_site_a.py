#!/usr/bin/env python3
"""
CHoRUS Validator - SITE_A Complete
Includes ALL labs from your queries
"""

import psycopg2
import pandas as pd

# COMPLETE SITE_A CONCEPTS - from your actual queries
SITE_A_CONCEPTS = {
    # TOP 30 MEASUREMENTS from your first query
    'top_vitals': {
        3020891: ('Body temperature', 13155082),
        2147483345: ('SpO2 Value (%)', 11885033),
        3004249: ('Systolic BP', 9078063),
        4224504: ('Pulse', 6247867),
        4196147: ('Peripheral O2 sat', 5742456),
        3012888: ('Diastolic BP', 5300302),
        2000000223: ('Vent Respirations', 5010120),
        4222965: ('Oxygen equipment', 3846770),
        3027018: ('Heart rate', 3106970),
        4264378: ('Urine output', 2203519),
        4353936: ('FiO2', 1495269),
        4108290: ('Invasive MAP', 1027371),
        36684829: ('RASS', 932034),
        4093836: ('GCS', 902439),
    },

    # PLATELETS - from your second query
    'platelets': {
        3024929: 489315, # PRIMARY - Platelets in Blood by Automated count
        3024386: 481004, # Platelet mean volume
        3016682: 354, # Platelets in Plasma
        3013290: 7974, # Old standard (fallback)
    },

    # LACTATE - from your third query
    'lactate': {
        3047181: 78297, # Lactate in Blood - PRIMARY
        3014111: 67316, # Lactate in Serum/Plasma - PRIMARY
        3022250: 32653, # LDH
        3008037: 2, # Venous lactate
    },

    # PaO2/SpO2 - from your fourth query
    'oxygen': {
        3027315: 7974, # PaO2 - PRIMARY
        3039426: 1112, # O2 sat arterial calc
        3011367: 10512, # O2 sat calc
        44786762: 22775, # Mixed venous
        2147483345: 11885033, # SpO2
    },

    # SOFA LABS
    'creatinine': [3016723, 3020564, 3051825],
    'bilirubin': [3024128, 3035616],
}

def validate_all(conn_str):
    conn = psycopg2.connect(conn_str)

    print("SITE_A COMPLETE VALIDATION")
    print("="*70)

    # Check platelets
    print("\nPLATELETS (should be 489,315):")
    for cid, expected in SITE_A_CONCEPTS['platelets'].items():
        df = pd.read_sql(f"SELECT COUNT(*) as n FROM omopcdm.measurement WHERE measurement_concept_id={cid}", conn)
        actual = df.iloc[0]['n']
        print(f" {cid}: {actual:,} (expected {expected:,}) {'OK' if actual==expected else 'MISMATCH'}")

    # Check lactate
    print("\nLACTATE (should be 145,613 total):")
    total = 0
    for cid, expected in SITE_A_CONCEPTS['lactate'].items():
        df = pd.read_sql(f"SELECT COUNT(*) as n FROM omopcdm.measurement WHERE measurement_concept_id={cid}", conn)
        actual = df.iloc[0]['n']
        total += actual
        print(f" {cid}: {actual:,} (expected {expected:,})")
    print(f" TOTAL: {total:,}")

    # Check PaO2
    print("\nPaO2 (should be 7,974):")
    df = pd.read_sql("SELECT COUNT(*) as n FROM omopcdm.measurement WHERE measurement_concept_id=3027315", conn)
    print(f" 3027315: {df.iloc[0]['n']:,}")

    # Check dopamine in DRUG_EXPOSURE (not measurement)
    print("\nDOPAMINE (check drug_exposure, not measurement):")
    df = pd.read_sql("""
        SELECT COUNT(*) as n FROM omopcdm.drug_exposure
        WHERE drug_concept_id IN (1319998, 1337860, 40240699)
    """, conn)
    print(f" Dopamine records: {df.iloc[0]['n']:,}")

    conn.close()

if __name__ == '__main__':
    validate_all("postgresql://postgres:password@host/db")
