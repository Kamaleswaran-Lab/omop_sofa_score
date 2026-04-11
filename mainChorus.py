#!/usr/bin/env python
# coding: utf-8

# Install and Load Required Packages

# In[ ]:


# Run this in a Jupyter cell to install
get_ipython().system('pip install polars')
get_ipython().system('pip install pandas numpy')

import os
import requests
import pandas as pd
import datetime
import seaborn as sns
import matplotlib.pyplot as plt
import requests
from pathlib import Path


# List of OMOP files
# 
# omop-condition-era-export.csv        
# omop-drug-era-export.csv     
# omop-observation-export.csv         
# omop-procedure-occurrence-export.csv
# omop-condition-occurrence-export.csv  
# omop-drug-exposure.csv       
# omop-observation-period-export.csv  
# omop-visit-detail-export.csv
# omop-death-export.csv                 
# omop-measurement-export.csv  
# omop-person-export.csv              
# omop-visit-occurrence-export.csv

# In[ ]:


# Check OMOP file
import pandas as pd

file_path = '/choruspilot/mgh/omop-person-export.csv'

try:
    # Read ONLY the first 1000 rows
    df_sample = pd.read_csv(file_path)#, nrows=1000)
    
    print("Successfully loaded sample!")
    print(df_sample.info())
    display(df_sample.head())

except Exception as e:
    print(f"An error occurred: {e}")


# In[ ]:


# Load all tables into a dictionary for easy access
from omop_utils import set_verbose 
from omop_calc_sofa import compute_daily_sofa, compute_hourly_sofa
from omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

import warnings
warnings.filterwarnings('ignore') # Silences the dateutil formatting warning

import pandas as pd
import numpy as np

# FIX: Grouped imports cleanly at the top
from omop_utils import set_verbose
from omop_calc_sofa import compute_daily_sofa
from omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

file_mapping = {
    'person': 'omop-person-export',
    'visit_occurrence': 'omop-visit-occurrence-export',
    'measurement': 'omop-measurement-export',
    'drug_exposure': 'omop-drug-exposure',
    'procedure_occurrence': 'omop-procedure-occurrence-export',
    'condition_occurrence': 'omop-condition-occurrence-export'
}

required_columns = {
    'person': [
        'person_id'
    ],
    'visit_occurrence': [
        'person_id',
        'visit_occurrence_id',
        'visit_start_datetime',
        'visit_end_datetime',
        'visit_concept_id'
    ],
    'measurement': [
        'person_id',
        'visit_occurrence_id',
        'measurement_concept_id',
        'measurement_datetime',
        'value_as_number',
        'unit_concept_id'
    ],
    'drug_exposure': [
        'person_id',
        'visit_occurrence_id',
        'drug_concept_id',
        'drug_exposure_start_datetime',
        'drug_exposure_end_datetime',
        'quantity',
        'dose_unit_concept_id',
        'route_concept_id',
        'sig'
    ],
    'procedure_occurrence': [
        'person_id',
        'visit_occurrence_id',
        'procedure_concept_id',
        'procedure_datetime'
    ],
    'condition_occurrence': [
        'person_id',
        'condition_concept_id'
    ]
}

datetime_columns = {
    'visit_occurrence': ['visit_start_datetime', 'visit_end_datetime'],
    'measurement': ['measurement_datetime'],
    'drug_exposure': ['drug_exposure_start_datetime', 'drug_exposure_end_datetime'],
    'procedure_occurrence': ['procedure_datetime']
}


def optimize_chunk_dtypes(chunk):
    """Reduce memory footprint by downcasting numeric columns in each chunk."""
    for col in chunk.columns:
        if col.endswith('_id'):
            chunk[col] = pd.to_numeric(chunk[col], errors='coerce', downcast='integer')
        elif col in ['value_as_number', 'quantity']:
            chunk[col] = pd.to_numeric(chunk[col], errors='coerce', downcast='float')
    return chunk


def load_omop_table(csv_path, table_name, chunksize=200000):
    """Load full OMOP table with only required columns and chunked processing."""
    header_cols = pd.read_csv(csv_path, nrows=0).columns.tolist()
    col_lookup = {c.lower(): c for c in header_cols}

    target_cols = required_columns[table_name]
    selected_actual_cols = [col_lookup[c] for c in target_cols if c in col_lookup]
    missing = [c for c in target_cols if c not in col_lookup]

    if missing:
        print(f"Warning: {table_name} missing columns: {missing}")

    chunks = []
    for chunk in pd.read_csv(csv_path, usecols=selected_actual_cols, chunksize=chunksize, low_memory=False):
        chunk.columns = [c.lower() for c in chunk.columns]
        chunk = optimize_chunk_dtypes(chunk)

        for dt_col in datetime_columns.get(table_name, []):
            if dt_col in chunk.columns:
                chunk[dt_col] = pd.to_datetime(chunk[dt_col], errors='coerce')

        chunks.append(chunk)

    if not chunks:
        return pd.DataFrame(columns=target_cols)

    return pd.concat(chunks, ignore_index=True)

cdm = {}
print("Loading tables...")

for standard_name, file_name in file_mapping.items():
    file_path = f'/choruspilot/mgh/{file_name}.csv'
    print(f"Loading full {standard_name} table from {file_path}...")
    df = load_omop_table(file_path, standard_name)
    mem_mb = df.memory_usage(deep=True).sum() / 1024 ** 2
    print(f"Loaded {standard_name}: {len(df):,} rows, {mem_mb:.1f} MB")

    cdm[standard_name] = df

# Handle the missing concept_ancestor safely
ancestor_df = pd.DataFrame() 



# In[ ]:


# Summary of the OMOP data
from omop_utils import set_verbose
set_verbose(True)

person_df = cdm['person']
visit_df = cdm['visit_occurrence']
measurement_df = cdm['measurement']
drug_df = cdm['drug_exposure']
procedure_df = cdm['procedure_occurrence']
condition_df = cdm['condition_occurrence']

print("="*60)
print("DATASET OVERVIEW")
print("="*60)
print(f"Total patients in CDM: {len(person_df)}")
print(f"Total visits: {len(visit_df)}")
print(f"Total measurements: {len(measurement_df)}")
print(f"Total drug exposures: {len(drug_df)}")
print(f"Total procedures: {len(procedure_df)}")
print(f"Total condition: {len(condition_df)}")

 
# Check date range
if not visit_df.empty:
    visit_df['visit_start_datetime'] = pd.to_datetime(visit_df['visit_start_datetime'])
    print(f"Date range: {visit_df['visit_start_datetime'].min()} to {visit_df['visit_start_datetime'].max()}")
    print(f"Patients with ICU visits: {visit_df['person_id'].nunique()}")
 
# Check measurement types
if not measurement_df.empty:
    print(f"\nTop measurement concepts:")
    top_meas = measurement_df['measurement_concept_id'].value_counts().head(10)
    for cid, count in top_meas.items():
        print(f"  {cid}: {count} records")
 
# Check drug types  
if not drug_df.empty:
    print(f"\nTop drug concepts:")
    top_drugs = drug_df['drug_concept_id'].value_counts().head(10)
    for cid, count in top_drugs.items():
        print(f"  {cid}: {count} records")
 
print("="*60)
 
from omop_utils import print_dataset_summary
print_dataset_summary(cdm)


# In[ ]:


# Analyze the data and find Sepsis-3 cases
set_verbose(True)

# Compute SOFA (hourly for accuracy, daily for reporting)
hourly_sofa = compute_hourly_sofa(cdm, ancestor_df)
daily_sofa = compute_daily_sofa(cdm, ancestor_df)

# Find infections
suspected = compute_suspected_infection(cdm, ancestor_df)

# Evaluate Sepsis-3 
sepsis3 = evaluate_sepsis3(hourly_sofa, suspected, cdm, ancestor_df)

# Display the results
display(sepsis3.head())


# In[ ]:

# 1. Save Hourly SOFA scores
hourly_sofa.to_csv('output_hourly_sofa.csv', index=False)
print("✅ Saved hourly_sofa -> 'output_hourly_sofa.csv'")

# 2. Save Daily SOFA scores
daily_sofa.to_csv('output_daily_sofa.csv', index=False)
print("✅ Saved daily_sofa -> 'output_daily_sofa.csv'")

# 3. Save Suspected Infections table
suspected.to_csv('output_suspected_infections.csv', index=False)
print("✅ Saved suspected -> 'output_suspected_infections.csv'")

# 4. Save Final Sepsis-3 Cohort
sepsis3.to_csv('output_sepsis3_cohort.csv', index=False)
print("✅ Saved sepsis3 -> 'output_sepsis3_cohort.csv'")

print("\n🎉 All tables have been successfully exported!")