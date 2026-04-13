"""
chorus_concepts.py
SITE_A CHoRUS - SOFA/Sepsis-3 concept mappings
Updated 2026-04-12 - Site A validated
"""

# SOFA COMPONENTS
PAO2_CONCEPTS = [
    3027315,    # Oxygen [Partial pressure] in Blood - Site A 7,974 PRIMARY
    3039426,    # O2 sat calc from PaO2 arterial - 1,112
    3011367,    # O2 sat calc from PaO2 - 10,512
    44786762,   # O2 sat calc mixed venous - 22,775
    3002647,    # Standard PaO2 (fallback)
    3021706,
    4097772,
    4103460,
]

FIO2_CONCEPTS = [
    4353936,    # Inspired oxygen concentration - Site A 1,495,269 PRIMARY
    3020719,
    3013465,
    2147482989,
]

CREATININE_CONCEPTS = [
    3016723,    # Creatinine [Mass/volume] in Serum or Plasma - Site A 549,112 PRIMARY
    3051825,
    3020564,
    4324383,
    2212294,
]

BILIRUBIN_CONCEPTS = [
    3024128,    # Bilirubin.total - Site A 239,317 PRIMARY
    3035616,
    3014661,
]

PLATELETS_CONCEPTS = [
    3024929,    # Platelets [#/volume] in Blood by Automated count - Site A 489,315 PRIMARY
    3024386,    # Platelet mean volume - Site A 481,004
    3013290,    # Standard platelets (fallback) - Site A 7,974
    3016682,    # Platelets in Plasma - 354
    40772688,
    40779159,
    4094430,
    4304094,
]

LACTATE_CONCEPTS = [
    3047181,    # Lactate [Moles/volume] in Blood - Site A 78,297 PRIMARY
    3014111,    # Lactate in Serum or Plasma - Site A 67,316 PRIMARY
    3022250,    # Lactate dehydrogenase - 32,653
    3008037,    # Lactate in Venous blood - 2
    4133534,    # Original IDs (fallback)
    4307161,
    4213582,
    4191725,
    1246795,
]

URINE_OUTPUT_CONCEPTS = [4264378]

# VASOPRESSORS
VASOPRESSOR_CONCEPTS = {
    'norepinephrine': [4328749, 1321341, 19010309, 740244, 740243],
    'epinephrine': [1338005, 19076899, 19123434],
    'vasopressin': [35202042, 35202043, 45775841, 1507835, 1507838, 19039813, 1360635],
    'phenylephrine': [1135766],
    'dopamine': [1319998, 1337860, 40240699, 40240703, 42799680, 42799676],
    'dobutamine': [1337720, 19076659],
}

VASOPRESSOR_NEE_FACTORS = {
    'norepinephrine': 1.0,
    'epinephrine': 1.0,
    'vasopressin': 2.5,
    'phenylephrine': 0.1,
    'dopamine': 0.01,
    'dobutamine': 0.01,
}

# VENTILATION
VENTILATOR_DEVICE_CONCEPTS = [4222965]
VENTILATOR_PROCEDURE_CONCEPTS = [4202832, 42738694]

# NEUROLOGICAL
GCS_CONCEPTS = [4093836, 3016335, 3009094, 3008223]
RASS_CONCEPTS = [36684829]

# RENAL
DIALYSIS_CONCEPTS = [4197217, 2109463]

# SEPSIS-3
CULTURE_CONCEPTS = [4046263, 4299649, 4189544, 4098207, 4029193, 4015188, 4296650]
ANTIBIOTIC_ANCESTOR = 21600381

# SUPPORT
MAP_CONCEPTS = [4108290, 36303772, 3027598]
WEIGHT_CONCEPTS = [4099154, 4086522]

# VITALS
SPO2_CONCEPTS = [2147483345, 4196147]
TEMPERATURE_CONCEPTS = [3020891, 3039856]
HEART_RATE_CONCEPTS = [3027018, 4224504]
RESP_RATE_CONCEPTS = [3024171, 2000000223, 2147483344]
SBP_CONCEPTS = [3004249]
DBP_CONCEPTS = [3012888]

def get_all_vasopressor_ids():
    ids = []
    for lst in VASOPRESSOR_CONCEPTS.values():
        ids.extend(lst)
    return list(set(ids))

def get_sofa_lab_ids():
    return {
        'creatinine': CREATININE_CONCEPTS,
        'bilirubin': BILIRUBIN_CONCEPTS,
        'platelets': PLATELETS_CONCEPTS,
        'pao2': PAO2_CONCEPTS,
        'fio2': FIO2_CONCEPTS,
        'lactate': LACTATE_CONCEPTS,
    }
