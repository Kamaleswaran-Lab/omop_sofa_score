import pandas as pd

# Load sample OMOP tables
cdm = {}
cdm['person'] = pd.read_csv('sample_data/person.csv')
cdm['visit_occurrence'] = pd.read_csv('sample_data/visit_occurrence.csv', parse_dates=['visit_start_datetime','visit_end_datetime'])
cdm['measurement'] = pd.read_csv('sample_data/measurement.csv', parse_dates=['measurement_datetime'])
cdm['drug_exposure'] = pd.read_csv('sample_data/drug_exposure.csv', parse_dates=['drug_exposure_start_datetime','drug_exposure_end_datetime'])
cdm['procedure_occurrence'] = pd.read_csv('sample_data/procedure_occurrence.csv', parse_dates=['procedure_datetime'])
cdm['condition_occurrence'] = pd.read_csv('sample_data/condition_occurrence.csv')
cdm['specimen'] = pd.read_csv('sample_data/specimen.csv', parse_dates=['specimen_datetime'])
cdm['concept_ancestor'] = pd.read_csv('sample_data/concept_ancestor.csv')

print("Loaded CDM tables:")
for k, v in cdm.items():
    print(f"{k}: {len(v)} rows")
