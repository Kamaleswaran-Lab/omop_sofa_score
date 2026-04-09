import sys
sys.path.append('../src')
import pandas as pd
from omop_calc_sofa import compute_daily_sofa

# Assume cdm is loaded from 01_load_data.py
# For tutorial, reload quickly
cdm = {}
for table in ['person','visit_occurrence','measurement','drug_exposure','procedure_occurrence','condition_occurrence','specimen','concept_ancestor']:
    cdm[table] = pd.read_csv(f'sample_data/{table}.csv', low_memory=False)

daily_sofa = compute_daily_sofa(cdm, cdm['concept_ancestor'])
daily_sofa.to_csv('output_daily_sofa.csv', index=False)
print(daily_sofa.head())
print(f"\nComputed SOFA for {daily_sofa['person_id'].nunique()} patients")
