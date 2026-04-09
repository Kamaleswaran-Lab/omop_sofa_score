import pandas as pd

# -------------------------------------------------------------------------
# Verified OHDSI Standard Concepts
# -------------------------------------------------------------------------
OHDSI_CONCEPTS = {
    'platelets': [3007461, 3024929],
    'bilirubin': [3024128],
    'creatinine': [3016723, 3020564, 3022243],
    'map': [3027598, 21492239],
    'gcs': [3032652, 41101853], 
    'pao2': [3012731],
    'fio2': [3016502],
    'urine_output': [3013466, 3013940, 21490854],
    
    # Base Ingredients - MUST be expanded via concept_ancestor in production
    'vasopressor_ingredients': [1321341, 1343916, 1337860, 1337720, 1507835, 11149],
    'antibiotic_ingredients': [1738622, 1713332, 1717327, 1707164], 
    
    'cultures': [3027114, 3013682, 3020891],
    'mech_vent_procedures': [4052536, 4233974]
}

VALID_UNITS = {
    'creatinine': [8840], # mg/dL
    'bilirubin': [8840],  # mg/dL
    'pao2': [8645]        # mmHg
}

def get_descendants(cdm_ancestor, ancestor_list):
    """Expands ingredient/procedure concepts to all valid clinical descendants."""
    if cdm_ancestor is not None:
        descendants = cdm_ancestor[cdm_ancestor['ancestor_concept_id'].isin(ancestor_list)]['descendant_concept_id']
        return list(set(ancestor_list + descendants.tolist()))
    return ancestor_list

def get_clean_measurements(cdm, concept_list, col_name, allowed_units=None):
    """Safely extracts measurements, enforcing unit standardization."""
    df = cdm['measurement'][cdm['measurement']['measurement_concept_id'].isin(concept_list)].copy()
    
    if allowed_units is not None and 'unit_concept_id' in df.columns:
        df = df[df['unit_concept_id'].isin(allowed_units) | df['unit_concept_id'].isna()]
        
    df = df[['person_id', 'visit_occurrence_id', 'measurement_datetime', 'value_as_number']]
    return df.rename(columns={'value_as_number': col_name, 'measurement_datetime': 'charttime'})
