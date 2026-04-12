"""
src/run_sofa_chunked.py - Production runner with chunking and audit logging
Prevents OOM on large databases
"""

import pandas as pd
import psycopg2
from omop_calc_sofa import compute_hourly_sofa
from omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3
from omop_utils import set_schemas, set_verbose
import time

def run_chunked(conn, person_ids=None, chunk_size=500, write_table='sofa_hourly'):
    """Process in chunks to avoid memory issues"""
    set_schemas()
    set_verbose(True)
    
    if person_ids is None:
        # Get all ICU patients
        person_ids = pd.read_sql("""
            SELECT DISTINCT person_id FROM omopcdm.visit_occurrence 
            WHERE visit_concept_id IN (32037, 32038) -- ICU visits
        """, conn)['person_id'].tolist()
    
    total = len(person_ids)
    print(f"Processing {total} patients in chunks of {chunk_size}")
    
    for i in range(0, total, chunk_size):
        chunk = person_ids[i:i+chunk_size]
        start = time.time()
        
        try:
            hourly = compute_hourly_sofa(conn, person_ids=chunk)
            if not hourly.empty:
                # Write hourly SOFA
                hourly.to_sql(write_table, conn, if_exists='append', index=False, method='multi')
                
                # Write assumptions
                assumptions = hourly[['person_id','visit_occurrence_id','charttime']].copy()
                assumptions['fio2_imputed'] = hourly['fio2'].isna()  # simplified
                assumptions['vaso_rate_source'] = hourly['ne_src']
                assumptions['pragmatic_mode'] = True
                assumptions.to_sql('sofa_assumptions', conn, if_exists='append', index=False, method='multi')
            
            elapsed = time.time() - start
            print(f"Chunk {i//chunk_size + 1}/{(total-1)//chunk_size + 1}: {len(chunk)} patients, {len(hourly)} hours, {elapsed:.1f}s")
            
        except Exception as e:
            print(f"ERROR chunk {i}: {e}")
            continue

if __name__ == "__main__":
    conn = psycopg2.connect(dbname="mgh", user="postgres")
    run_chunked(conn, chunk_size=500)
