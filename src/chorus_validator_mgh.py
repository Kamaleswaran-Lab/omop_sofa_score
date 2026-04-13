#!/usr/bin/env python3
"""
CHoRUS Validator - MGH Specific
Validates SOFA score components and key ICU labs in OMOP CDM
Updated for MGH concept IDs based on actual data counts (2026-04-12)

Dr. Rishi Kamaleswaran, Ph.D.
"""

import psycopg2
import pandas as pd
from datetime import datetime

# MGH-SPECIFIC CONCEPT IDS - validated against actual counts
CHORUS_CONCEPTS = {
    'labs': {
        'creatinine': {
            'ids': [3016723, 3020564, 3051825, 3004327],
            'name': 'Creatinine',
            'mgh_count': 549112,
            'unit': 'mg/dL',
            'sofa': True
        },
        'bilirubin_total': {
            'ids': [3024128, 3035616, 3014661],
            'name': 'Bilirubin Total',
            'mgh_count': 239317,
            'unit': 'mg/dL',
            'sofa': True
        },
        'platelets': {
            'ids': [3024929, 3013290, 3024386, 3016682],  # 3024929 is MGH primary (489k)
            'name': 'Platelets',
            'mgh_count': 489315,
            'unit': '10^3/uL',
            'sofa': True,
            'note': 'MGH uses 3024929, not 3013290'
        },
        'lactate': {
            'ids': [3047181, 3014111, 3022250, 3008037],  # MGH has 145k total
            'name': 'Lactate',
            'mgh_count': 145613,
            'unit': 'mmol/L',
            'sofa': False,
            'note': '3047181 (blood) + 3014111 (serum)'
        },
        'pao2': {
            'ids': [3027315, 3039426, 3011367, 44786762, 3002647],  # 3027315 is MGH primary
            'name': 'PaO2',
            'mgh_count': 7974,
            'unit': 'mmHg',
            'sofa': True,
            'note': 'MGH uses 3027315, not 3002647'
        },
        'fio2': {
            'ids': [4353936, 3020719, 3013465],
            'name': 'FiO2',
            'mgh_count': 1495269,
            'unit': '%',
            'sofa': True
        }
    },
    'vitals': {
        'spo2': {
            'ids': [2147483345, 4196147],
            'name': 'SpO2',
            'mgh_count': 17627489,
            'unit': '%'
        },
        'map': {
            'ids': [4108290, 3012888, 3004249],
            'name': 'MAP',
            'mgh_count': 1027371,
            'unit': 'mmHg',
            'sofa': True
        },
        'sbp': {
            'ids': [3004249],
            'name': 'SBP',
            'mgh_count': 9078063,
            'unit': 'mmHg'
        },
        'dbp': {
            'ids': [3012888],
            'name': 'DBP',
            'mgh_count': 5300302,
            'unit': 'mmHg'
        },
        'heart_rate': {
            'ids': [3027018, 4224504],
            'name': 'Heart Rate',
            'mgh_count': 9354837,
            'unit': 'bpm'
        },
        'resp_rate': {
            'ids': [3024171, 2147483344, 2000000223],
            'name': 'Respiratory Rate',
            'mgh_count': 7540820,
            'unit': '/min'
        },
        'temperature': {
            'ids': [3020891, 3039856],
            'name': 'Temperature',
            'mgh_count': 14680602,
            'unit': 'C'
        }
    },
    'neuro': {
        'gcs_total': {
            'ids': [4093836, 3032653],
            'name': 'GCS Total',
            'mgh_count': 902439,
            'sofa': True
        },
        'rass': {
            'ids': [36684829],
            'name': 'RASS',
            'mgh_count': 932034
        }
    },
    'vasopressors': {
        'norepinephrine': [35897581, 4021963],
        'epinephrine': [35897579, 4022245],
        'dopamine': [35897578, 4022235],
        'vasopressin': [35897584],
        'phenylephrine': [35897582]
    }
}

class ChorusValidator:
    def __init__(self, conn_string):
        self.conn_string = conn_string
        self.conn = None
        
    def connect(self):
        """Connect to PostgreSQL - prompts for password"""
        try:
            self.conn = psycopg2.connect(self.conn_string)
            print(f"â Connected to MGH OMOP CDM")
            return True
        except Exception as e:
            print(f"â Connection failed: {e}")
            return False
    
    def validate_labs(self):
        """Validate all SOFA labs with MGH-specific IDs"""
        print("
" + "="*70)
        print("MGH LAB VALIDATION - SOFA Components")
        print("="*70)
        
        results = []
        for key, lab in CHORUS_CONCEPTS['labs'].items():
            ids_str = ','.join(map(str, lab['ids']))
            query = f"""
                SELECT 
                    '{lab['name']}' as lab,
                    COUNT(*) as actual_count,
                    COUNT(DISTINCT person_id) as patients,
                    MIN(measurement_date) as first_date,
                    MAX(measurement_date) as last_date,
                    ROUND(AVG(value_as_number)::numeric, 2) as mean_value
                FROM omopcdm.measurement
                WHERE measurement_concept_id IN ({ids_str})
                AND value_as_number IS NOT NULL
            """
            try:
                df = pd.read_sql(query, self.conn)
                actual = df.iloc[0]['actual_count']
                expected = lab['mgh_count']
                diff_pct = abs(actual - expected) / expected * 100 if expected > 0 else 0
                
                status = "â" if diff_pct < 10 else "â " if diff_pct < 25 else "â"
                
                results.append({
                    'Lab': lab['name'],
                    'Expected': f"{expected:,}",
                    'Actual': f"{actual:,}",
                    'Diff %': f"{diff_pct:.1f}%",
                    'Patients': f"{df.iloc[0]['patients']:,}",
                    'Mean': df.iloc[0]['mean_value'],
                    'Status': status,
                    'SOFA': 'Yes' if lab.get('sofa') else 'No'
                })
                
                print(f"{status} {lab['name']:<20} Expected: {expected:>9,} | Actual: {actual:>9,} | {diff_pct:>5.1f}% diff")
                if lab.get('note'):
                    print(f"  â {lab['note']}")
                    
            except Exception as e:
                print(f"â {lab['name']}: {e}")
        
        return pd.DataFrame(results)
    
    def validate_vitals(self):
        """Validate vital signs"""
        print("
" + "="*70)
        print("MGH VITALS VALIDATION")
        print("="*70)
        
        for key, vital in CHORUS_CONCEPTS['vitals'].items():
            ids_str = ','.join(map(str, vital['ids']))
            query = f"""
                SELECT COUNT(*) as n
                FROM omopcdm.measurement
                WHERE measurement_concept_id IN ({ids_str})
            """
            try:
                df = pd.read_sql(query, self.conn)
                actual = df.iloc[0]['n']
                expected = vital['mgh_count']
                print(f"â {vital['name']:<25} {actual:>12,} records (expected ~{expected:,})")
            except Exception as e:
                print(f"â {vital['name']}: {e}")
    
    def check_pao2_fio2_ratio(self):
        """Check PaO2/FiO2 availability for respiratory SOFA"""
        print("
" + "="*70)
        print("PaO2/FiO2 RATIO AVAILABILITY (Respiratory SOFA)")
        print("="*70)
        
        query = """
        WITH pao2 AS (
            SELECT person_id, measurement_datetime, value_as_number as pao2
            FROM omopcdm.measurement
            WHERE measurement_concept_id IN (3027315, 3039426, 3011367)
            AND value_as_number BETWEEN 20 AND 500
        ),
        fio2 AS (
            SELECT person_id, measurement_datetime, value_as_number as fio2
            FROM omopcdm.measurement
            WHERE measurement_concept_id = 4353936
            AND value_as_number BETWEEN 21 AND 100
        )
        SELECT 
            COUNT(DISTINCT p.person_id) as patients_with_both,
            COUNT(*) as paired_measurements
        FROM pao2 p
        JOIN fio2 f ON p.person_id = f.person_id
        AND ABS(EXTRACT(EPOCH FROM (p.measurement_datetime - f.measurement_datetime))/60) < 60
        """
        
        try:
            df = pd.read_sql(query, self.conn)
            print(f"Patients with PaO2+FiO2 within 1 hour: {df.iloc[0]['patients_with_both']:,}")
            print(f"Total paired measurements: {df.iloc[0]['paired_measurements']:,}")
            print(f"Note: MGH PaO2 count is low (7,974) - mostly on vented patients")
        except Exception as e:
            print(f"Error: {e}")
    
    def check_data_quality(self):
        """Check for common OMOP issues at MGH"""
        print("
" + "="*70)
        print("DATA QUALITY CHECKS")
        print("="*70)
        
        checks = [
            ("Total measurements", "SELECT COUNT(*) FROM omopcdm.measurement"),
            ("Measurements with values", "SELECT COUNT(*) FROM omopcdm.measurement WHERE value_as_number IS NOT NULL"),
            ("Distinct patients in measurement", "SELECT COUNT(DISTINCT person_id) FROM omopcdm.measurement"),
            ("Date range", "SELECT MIN(measurement_date), MAX(measurement_date) FROM omopcdm.measurement"),
            ("Top concept (should be temp)", "SELECT measurement_concept_id, COUNT(*) FROM omopcdm.measurement GROUP BY 1 ORDER BY 2 DESC LIMIT 1")
        ]
        
        for name, sql in checks:
            try:
                df = pd.read_sql(sql, self.conn)
                if 'COUNT' in sql.upper():
                    print(f"â {name:<35} {df.iloc[0,0]:,}")
                else:
                    print(f"â {name:<35} {df.iloc[0,0]} to {df.iloc[0,1]}")
            except Exception as e:
                print(f"â {name}: {e}")
    
    def generate_sofa_query(self):
        """Generate SOFA query with MGH IDs"""
        print("
" + "="*70)
        print("SOFA QUERY TEMPLATE (MGH IDs)")
        print("="*70)
        
        template = """
-- SOFA Score Components - MGH OMOP CDM
-- Use these concept IDs for MGH

WITH labs AS (
    SELECT 
        person_id,
        measurement_datetime,
        -- Creatinine (renal)
        MAX(CASE WHEN measurement_concept_id IN (3016723) 
            THEN value_as_number END) as creatinine,
        -- Bilirubin (liver)  
        MAX(CASE WHEN measurement_concept_id IN (3024128)
            THEN value_as_number END) as bilirubin,
        -- Platelets (coagulation) - MGH uses 3024929
        MAX(CASE WHEN measurement_concept_id IN (3024929, 3013290)
            THEN value_as_number END) as platelets,
        -- PaO2 (respiratory) - MGH uses 3027315
        MAX(CASE WHEN measurement_concept_id IN (3027315)
            THEN value_as_number END) as pao2,
        -- Lactate
        MAX(CASE WHEN measurement_concept_id IN (3047181, 3014111)
            THEN value_as_number END) as lactate
    FROM omopcdm.measurement
    WHERE measurement_concept_id IN (
        3016723, 3024128, 3024929, 3013290, 
        3027315, 3047181, 3014111
    )
    AND value_as_number IS NOT NULL
    GROUP BY person_id, measurement_datetime
)
SELECT * FROM labs
WHERE creatinine IS NOT NULL 
   OR bilirubin IS NOT NULL 
   OR platelets IS NOT NULL;
"""
        print(template)
        return template
    
    def close(self):
        if self.conn:
            self.conn.close()

def main():
    print("CHoRUS Validator - Massachusetts General Hospital")
    print(f"Run date: {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print()
    
    # Connection string - password will be prompted
    conn_str = "postgresql://postgres@psql-chorus-main.postgres.database.azure.com/mgh"
    
    validator = ChorusValidator(conn_str)
    
    if not validator.connect():
        return
    
    try:
        # Run validations
        validator.check_data_quality()
        labs_df = validator.validate_labs()
        validator.validate_vitals()
        validator.check_pao2_fio2_ratio()
        validator.generate_sofa_query()
        
        print("
" + "="*70)
        print("VALIDATION COMPLETE")
        print("="*70)
        print("
Key MGH findings:")
        print("â¢ Platelets: USE 3024929 (489k), not 3013290 (8k)")
        print("â¢ Lactate: USE 3047181 + 3014111 (146k total)")
        print("â¢ PaO2: USE 3027315 (8k), not 3002647")
        print("â¢ Creatinine 549k and Bilirubin 239k are correct for MGH ICU")
        
    finally:
        validator.close()

if __name__ == "__main__":
    main()
