"""
validate_concepts.py
MGH CHoRUS - FINAL with all SOFA/Sepsis-3 concepts
"""

import sys
import argparse
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

CHORUS_OVERRIDES = {
    3002647: [3002647, 3021706, 4097772, 4103460, 4094585, 3038071, 1616654],
    3013468: [4353936, 2147482989, 3026238],
    3016723: [3016723, 3051825, 3020564, 4324383, 2212294],
    3024128: [3024128],
    3013290: [3013290, 40772688, 40779159, 4094430, 4304094],
    4065485: [4264378],
    4328749: [4328749, 1321341, 19010309, 740244, 740243],
    1338005: [1338005, 19076899, 19123434],
    1360635: [35202042, 35202043, 45775841, 1507835, 1507838, 19039813],
    1335616: [1135766],
    1319998: [1319998, 1337860, 40240699, 40240703, 42799680, 42799676],
    45768131: [4222965],
    4302207: [4202832, 42738694],
    4253928: [4093836, 3016335, 3009094, 3008223],
    40488434: [36684829],
    4146536: [4197217, 2109463],
    4046263: [4046263, 4299649, 4189544, 4098207, 4029193, 4015188, 4296650],
    3013762: [4099154, 4086522],
    3027598: [4108290, 36303772],
}

# Add lactate as extra check
CHORUS_OVERRIDES[999999] = [4133534, 4307161, 4213582, 4191725, 1246795]

def main():
    import argparse
    from sqlalchemy import create_engine, text
    
    parser = argparse.ArgumentParser()
    parser.add_argument('--connection-string', required=True)
    parser.add_argument('--cdm-schema', default='omopcdm')
    args = parser.parse_args()
    
    engine = create_engine(args.connection_string)
    
    concepts = [
        (3002647, 'PaO2', 'measurement', 'measurement_concept_id'),
        (3013468, 'FiO2', 'measurement', 'measurement_concept_id'),
        (3016723, 'Creatinine', 'measurement', 'measurement_concept_id'),
        (3024128, 'Bilirubin', 'measurement', 'measurement_concept_id'),
        (3013290, 'Platelets', 'measurement', 'measurement_concept_id'),
        (4065485, 'Urine Output', 'measurement', 'measurement_concept_id'),
        (999999, 'Lactate', 'measurement', 'measurement_concept_id'),
        (4328749, 'Norepinephrine', 'drug_exposure', 'drug_concept_id'),
        (1338005, 'Epinephrine', 'drug_exposure', 'drug_concept_id'),
        (1360635, 'Vasopressin', 'drug_exposure', 'drug_concept_id'),
        (1335616, 'Phenylephrine', 'drug_exposure', 'drug_concept_id'),
        (1319998, 'Dopamine', 'drug_exposure', 'drug_concept_id'),
        (45768131, 'Ventilator', 'device_exposure', 'device_concept_id'),
        (4253928, 'GCS', 'observation', 'observation_concept_id'),
        (40488434, 'RASS', 'observation', 'observation_concept_id'),
    ]
    
    logger.info("=" * 70)
    logger.info("MGH SOFA/Sepsis-3 Concept Validation")
    logger.info("=" * 70)
    
    with engine.connect() as conn:
        for cid, name, table, col in concepts:
            ids = CHORUS_OVERRIDES.get(cid, [cid])
            ids_str = ','.join(map(str, ids))
            count = conn.execute(text(f"SELECT COUNT(*) FROM {args.cdm_schema}.{table} WHERE {col} IN ({ids_str})")).scalar()
            status = "[OK]" if count > 0 else "[X]"
            logger.info(f"{status} {name:20} | {count:10,} records | {len(ids)} concepts")

if __name__ == '__main__':
    main()
