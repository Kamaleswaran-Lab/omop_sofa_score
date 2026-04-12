"""
chorus_concepts.py
CHoRUS-specific OMOP concept overrides
Place in src/
"""

VASOPRESSOR_CONCEPTS = {
    'norepinephrine': [4328749, 1343916, 1349624],
    'epinephrine': [1338005],
    'vasopressin': [1360635, 35202042, 35202043, 45775841, 1507835, 1507838, 19039813],
    'phenylephrine': [1335616],
    'dopamine': [1319998],
    'dobutamine': [1314012],
}

VASOPRESSOR_NEE_FACTORS = {
    'norepinephrine': 1.0,
    'epinephrine': 1.0,
    'vasopressin': 2.5,
    'phenylephrine': 0.1,
    'dopamine': 0.01,
    'dobutamine': 0.01,
}

def get_all_vasopressor_ids():
    ids = []
    for lst in VASOPRESSOR_CONCEPTS.values():
        ids.extend(lst)
    return list(set(ids))

def get_vasopressor_type(concept_id):
    for name, ids in VASOPRESSOR_CONCEPTS.items():
        if concept_id in ids:
            return name
    return 'unknown'

def get_nee_factor(concept_id):
    drug_type = get_vasopressor_type(concept_id)
    return VASOPRESSOR_NEE_FACTORS.get(drug_type, 0.0)
