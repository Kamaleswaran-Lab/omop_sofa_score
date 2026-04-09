import sys
sys.path.append('../src')
import pandas as pd
from omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

cdm = {}
for table in ['person','visit_occurrence','measurement','drug_exposure','procedure_occurrence','condition_occurrence','specimen','concept_ancestor']:
    cdm[table] = pd.read_csv(f'sample_data/{table}.csv', low_memory=False)

daily_sofa = pd.read_csv('output_daily_sofa.csv', parse_dates=['chartdate'])
suspected = compute_suspected_infection(cdm, cdm['concept_ancestor'])
sepsis3 = evaluate_sepsis3(daily_sofa, suspected, cdm, cdm['concept_ancestor'])

sepsis3.to_csv('output_sepsis3.csv', index=False)
print(sepsis3)
print(f"\nSepsis-3 cases: {sepsis3['is_sepsis3'].sum()}")
