"""
validate_concepts.py

Check if OMOP site has required concepts for SOFA calculation
CHoRUS Edition - handles incomplete concept_ancestor tables
"""

import sys
import argparse
from typing import Dict, Tuple
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

REQUIRED_CONCEPTS = {
    'Core Labs': {
        3002647: 'PaO2 (arterial oxygen)',
        3013468: 'FiO2 (fraction inspired oxygen)',
        3016723: 'Creatinine',
        3024128: 'Bilirubin total',
        3013290: 'Platelets',
        4065485: 'Urine output',
    },
    'Vasopressors (FIX #1)': {
        4328749: 'Norepinephrine',
        1338005: 'Epinephrine',
        1360635: 'Vasopressin (CRITICAL - was excluded in v3.5)',
        1335616: 'Phenylephrine',
        1319998: 'Dopamine',
    },
    'Ventilation (FIX #9)': {
        45768131: 'Mechanical ventilation (device)',
        4302207: 'Ventilation procedure',
    },
    'Neurological (FIX #4)': {
        4253928: 'Glasgow Coma Scale',
        40488434: 'RASS (Richmond Agitation-Sedation)',
    },
    'Renal (FIX #6)': {
        4146536: 'Dialysis procedure (RRT)',
    },
    'Sepsis-3': {
        21600381: 'Antibacterial agents',
        4046263: 'Microbiology culture',
    },
    'Support': {
        3013762: 'Body weight (for dose normalization)',
        3027598: 'Mean arterial pressure',
    }
}

CHORUS_OVERRIDES = {
    1360635: [1360635, 35202042, 35202043, 45775841, 1507835, 1507838, 19039813],
    4328749: [4328749, 1343916, 1349624],
    1338005: [1338005],
    3002647: [3002647, 3023091, 3003461],
    3013468: [3013468, 3025329],
    1335616: [1335616],
    1319998: [1319998],
}

class ConceptValidator:
    def __init__(self, connection_string: str, cdm_schema: str = 'cdm', vocab_schema: str = 'vocab'):
        self.connection_string = connection_string
        self.cdm_schema = cdm_schema
        self.vocab_schema = vocab_schema
        self.engine = None

    def connect(self):
        try:
            from sqlalchemy import create_engine
            self.engine = create_engine(self.connection_string)
            logger.info("Connected to database")
            return True
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            return False

    def check_concept_exists(self, concept_id: int) -> Tuple[bool, int, int]:
        from sqlalchemy import text
        
        with self.engine.connect() as conn:
            result = conn.execute(
                text(f"SELECT COUNT(*) FROM {self.vocab_schema}.concept WHERE concept_id = :id"),
                {'id': concept_id}
            ).scalar()
            
            exists = result > 0
            if not exists:
                return False, 0, 0

            concept_ids_to_check = CHORUS_OVERRIDES.get(concept_id, [concept_id])
            ids_str = ','.join(str(x) for x in concept_ids_to_check)
            
            descendants = conn.execute(
                text(f"SELECT COUNT(DISTINCT descendant_concept_id) FROM {self.vocab_schema}.concept_ancestor WHERE ancestor_concept_id IN ({ids_str})")
            ).scalar() or 0
            
            if descendants == 0:
                descendants = 1

            record_count = 0
            
            if concept_id in [3002647, 3013468, 3016723, 3024128, 3013290, 4065485, 3013762, 3027598]:
                record_count = conn.execute(
                    text(f"SELECT COUNT(*) FROM {self.cdm_schema}.measurement m LEFT JOIN {self.vocab_schema}.concept_ancestor ca ON ca.descendant_concept_id = m.measurement_concept_id WHERE ca.ancestor_concept_id IN ({ids_str}) OR m.measurement_concept_id IN ({ids_str})")
                ).scalar() or 0
            
            elif concept_id in [4328749, 1338005, 1360635, 1335616, 1319998, 21600381]:
                record_count = conn.execute(
                    text(f"SELECT COUNT(*) FROM {self.cdm_schema}.drug_exposure d LEFT JOIN {self.vocab_schema}.concept_ancestor ca ON ca.descendant_concept_id = d.drug_concept_id WHERE ca.ancestor_concept_id IN ({ids_str}) OR d.drug_concept_id IN ({ids_str})")
                ).scalar() or 0
            
            elif concept_id in [45768131, 4302207, 4146536, 4046263]:
                table = 'procedure_occurrence' if concept_id != 45768131 else 'device_exposure'
                concept_col = 'procedure_concept_id' if concept_id != 45768131 else 'device_concept_id'
                
                record_count = conn.execute(
                    text(f"SELECT COUNT(*) FROM {self.cdm_schema}.{table} p LEFT JOIN {self.vocab_schema}.concept_ancestor ca ON ca.descendant_concept_id = p.{concept_col} WHERE ca.ancestor_concept_id IN ({ids_str}) OR p.{concept_col} IN ({ids_str})")
                ).scalar() or 0
            
            elif concept_id in [4253928, 40488434]:
                record_count = conn.execute(
                    text(f"SELECT COUNT(*) FROM {self.cdm_schema}.observation o LEFT JOIN {self.vocab_schema}.concept_ancestor ca ON ca.descendant_concept_id = o.observation_concept_id WHERE ca.ancestor_concept_id IN ({ids_str}) OR o.observation_concept_id IN ({ids_str})")
                ).scalar() or 0

            return True, descendants, record_count

    def validate_all(self) -> Dict:
        results = {}
        
        logger.info("=" * 70)
        logger.info("OMOP SOFA Concept Validation")
        logger.info("=" * 70)
        
        for category, concepts in REQUIRED_CONCEPTS.items():
            logger.info("")
            logger.info(f"{category}:")
            logger.info("-" * 70)
            
            category_results = []
            
            for concept_id, description in concepts.items():
                exists, descendants, count = self.check_concept_exists(concept_id)
                
                if exists and count > 0:
                    status = "[OK]"
                elif not exists:
                    status = "[X]"
                else:
                    status = "[!]"
                
                warning = ""
                if concept_id == 1360635 and count == 0:
                    warning = "  WARNING: Vasopressin missing! Cardio SOFA will be wrong"
                elif concept_id == 1360635 and count > 0:
                    warning = f"  Found {count} vasopressin records (CHoRUS override active)"
                
                logger.info(f"  {status} {concept_id:8} | {description:45} | descendants: {descendants:5} | records: {count:8,}{warning}")
                
                category_results.append({
                    'concept_id': concept_id,
                    'description': description,
                    'exists': exists,
                    'descendants': descendants,
                    'record_count': count,
                    'critical': concept_id == 1360635
                })
            
            results[category] = category_results
        
        return results

    def print_summary(self, results: Dict):
        logger.info("")
        logger.info("=" * 70)
        logger.info("VALIDATION SUMMARY")
        logger.info("=" * 70)
        
        total_concepts = sum(len(concepts) for concepts in REQUIRED_CONCEPTS.values())
        found_concepts = sum(sum(1 for r in cat_results if r['exists']) for cat_results in results.values())
        concepts_with_data = sum(sum(1 for r in cat_results if r['record_count'] > 0) for cat_results in results.values())
        
        logger.info("")
        logger.info(f"Concepts found in vocabulary: {found_concepts}/{total_concepts}")
        logger.info(f"Concepts with data: {concepts_with_data}/{total_concepts}")
        
        critical_missing = []
        for category, cat_results in results.items():
            for result in cat_results:
                if result['critical'] and result['record_count'] == 0:
                    critical_missing.append(result['description'])
        
        if critical_missing:
            logger.error("")
            logger.error("CRITICAL ISSUES FOUND:")
            for item in critical_missing:
                logger.error(f"  - {item}")
            logger.error("")
            logger.error("These will cause incorrect SOFA calculations!")
        else:
            logger.info("")
            logger.info("All critical concepts have data")
        
        logger.info("")
        logger.info("Data availability:")
        for category, cat_results in results.items():
            with_data = sum(1 for r in cat_results if r['record_count'] > 0)
            total = len(cat_results)
            pct = (with_data / total * 100) if total > 0 else 0
            logger.info(f"  {category:25} {with_data}/{total} concepts have data ({pct:.0f}%)")
        
        logger.info("")
        logger.info("=" * 70)
        logger.info("RECOMMENDATIONS")
        logger.info("=" * 70)
        
        vaso_result = None
        for cat_results in results.values():
            for r in cat_results:
                if r['concept_id'] == 1360635:
                    vaso_result = r
                    break
        
        if vaso_result and vaso_result['record_count'] == 0:
            logger.warning("")
            logger.warning("1. Vasopressin: No data found")
            logger.warning("   - Cardio SOFA will be underestimated in septic shock")
            logger.warning("   - Check CHORUS_OVERRIDES in validate_concepts.py")
        elif vaso_result:
            logger.info("")
            logger.info(f"1. Vasopressin: Found {vaso_result['record_count']} records")
        
        fio2_result = None
        for cat_results in results.values():
            for r in cat_results:
                if r['concept_id'] == 3013468:
                    fio2_result = r
                    break
        
        if fio2_result and fio2_result['record_count'] == 0:
            logger.warning("")
            logger.warning("2. FiO2: No data found")
            logger.warning("   - Respiratory SOFA will be NULL for most patients")
            logger.warning("   - This is CORRECT (no imputation), but reduces sample size")
        
        logger.info("")
        logger.info("Validation complete")

def main():
    parser = argparse.ArgumentParser(description='Validate OMOP concepts for SOFA calculation')
    parser.add_argument('--connection-string', required=True, help='PostgreSQL connection string')
    parser.add_argument('--cdm-schema', default='cdm', help='CDM schema name')
    parser.add_argument('--vocab-schema', default='vocab', help='Vocabulary schema name')
    
    args = parser.parse_args()
    
    validator = ConceptValidator(
        connection_string=args.connection_string,
        cdm_schema=args.cdm_schema,
        vocab_schema=args.vocab_schema
    )
    
    if not validator.connect():
        sys.exit(1)
    
    results = validator.validate_all()
    validator.print_summary(results)

if __name__ == '__main__':
    main()
