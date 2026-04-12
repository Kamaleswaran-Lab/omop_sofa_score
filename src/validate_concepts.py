"""
validate_concepts.py
Check if OMOP site has required concepts for SOFA calculation

Validates:
- Core lab concepts (PaO2, FiO2, creatinine, etc.)
- Vasopressor concepts (including vasopressin)
- Ventilation concepts
- Neuro concepts (GCS, RASS)
- Sepsis-3 concepts (antibiotics, cultures)
"""

import sys
import argparse
from typing import Dict, List, Tuple
import logging

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Required concepts for SOFA calculation
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

class ConceptValidator:
    """Validate OMOP site has required concepts"""
    
    def __init__(self, connection_string: str, 
                 cdm_schema: str = 'cdm',
                 vocab_schema: str = 'vocab'):
        self.connection_string = connection_string
        self.cdm_schema = cdm_schema
        self.vocab_schema = vocab_schema
        self.engine = None
    
    def connect(self):
        """Connect to database"""
        try:
            from sqlalchemy import create_engine
            self.engine = create_engine(self.connection_string)
            logger.info(f"Connected to database")
            return True
        except Exception as e:
            logger.error(f"Connection failed: {e}")
            return False
    
    def check_concept_exists(self, concept_id: int) -> Tuple[bool, int, int]:
        """
        Check if concept exists and has descendants
        
        Returns: (exists, descendant_count, measurement_count)
        """
        from sqlalchemy import text
        
        with self.engine.connect() as conn:
            # Check if concept exists in vocabulary
            result = conn.execute(
                text(f"SELECT COUNT(*) FROM {self.vocab_schema}.concept WHERE concept_id = :id"),
                {'id': concept_id}
            ).scalar()
            
            exists = result > 0
            
            if not exists:
                return False, 0, 0
            
            # Count descendants
            descendants = conn.execute(
                text(f"""
                    SELECT COUNT(DISTINCT descendant_concept_id) 
                    FROM {self.vocab_schema}.concept_ancestor 
                    WHERE ancestor_concept_id = :id
                """),
                {'id': concept_id}
            ).scalar()
            
            # Count measurements (if applicable)
            measurement_count = 0
            if concept_id in [3002647, 3013468, 3016723, 3024128, 3013290, 4065485]:
                # Lab concepts
                measurement_count = conn.execute(
                    text(f"""
                        SELECT COUNT(*) FROM {self.cdm_schema}.measurement m
                        JOIN {self.vocab_schema}.concept_ancestor ca 
                            ON ca.descendant_concept_id = m.measurement_concept_id
                        WHERE ca.ancestor_concept_id = :id
                    """),
                    {'id': concept_id}
                ).scalar()
            elif concept_id in [4328749, 1338005, 1360635, 1335616, 1319998]:
                # Drug concepts
                measurement_count = conn.execute(
                    text(f"""
                        SELECT COUNT(*) FROM {self.cdm_schema}.drug_exposure d
                        JOIN {self.vocab_schema}.concept_ancestor ca 
                            ON ca.descendant_concept_id = d.drug_concept_id
                        WHERE ca.ancestor_concept_id = :id
                    """),
                    {'id': concept_id}
                ).scalar()
            
            return True, descendants, measurement_count
    
    def validate_all(self) -> Dict:
        """Validate all required concepts"""
        results = {}
        
        logger.info("=" * 70)
        logger.info("OMOP SOFA Concept Validation")
        logger.info("=" * 70)
        
        for category, concepts in REQUIRED_CONCEPTS.items():
            logger.info(f"\n{category}:")
            logger.info("-" * 70)
            
            category_results = []
            
            for concept_id, description in concepts.items():
                exists, descendants, count = self.check_concept_exists(concept_id)
                
                status = "â" if exists and descendants > 0 else "â"
                status_color = "\033[92m" if exists and descendants > 0 else "\033[91m"
                
                # Special warning for vasopressin
                warning = ""
                if concept_id == 1360635 and (not exists or descendants == 0):
                    warning = " â  CRITICAL: Vasopressin missing! Cardio SOFA will be wrong"
                elif concept_id == 1360635 and count == 0:
                    warning = " â  No vasopressin data found"
                
                logger.info(f"  {status} {concept_id:8} | {description:45} | "
                           f"descendants: {descendants:5} | records: {count:8,}{warning}")
                
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
        """Print validation summary"""
        logger.info("\n" + "=" * 70)
        logger.info("VALIDATION SUMMARY")
        logger.info("=" * 70)
        
        total_concepts = sum(len(concepts) for concepts in REQUIRED_CONCEPTS.values())
        found_concepts = sum(
            sum(1 for r in cat_results if r['exists'] and r['descendants'] > 0)
            for cat_results in results.values()
        )
        
        logger.info(f"\nConcepts found: {found_concepts}/{total_concepts}")
        
        # Check critical concepts
        critical_missing = []
        for category, cat_results in results.items():
            for result in cat_results:
                if result['critical'] and (not result['exists'] or result['descendants'] == 0):
                    critical_missing.append(result['description'])
        
        if critical_missing:
            logger.error("\nâ  CRITICAL ISSUES FOUND:")
            for issue in critical_missing:
                logger.error(f"  - {issue}")
            logger.error("\nThese will cause incorrect SOFA calculations!")
        else:
            logger.info("\nâ All critical concepts present")
        
        # Check data availability
        logger.info("\nData availability:")
        for category, cat_results in results.items():
            with_data = sum(1 for r in cat_results if r['record_count'] > 0)
            total = len(cat_results)
            pct = (with_data / total * 100) if total > 0 else 0
            logger.info(f"  {category:25} {with_data}/{total} concepts have data ({pct:.0f}%)")
        
        # Recommendations
        logger.info("\n" + "=" * 70)
        logger.info("RECOMMENDATIONS")
        logger.info("=" * 70)
        
        # Check vasopressin specifically
        vaso_result = None
        for cat_results in results.values():
            for r in cat_results:
                if r['concept_id'] == 1360635:
                    vaso_result = r
                    break
        
        if vaso_result:
            if vaso_result['record_count'] == 0:
                logger.warning("\n1. Vasopressin: No data found")
                logger.warning("   - Cardio SOFA will be underestimated in septic shock")
                logger.warning("   - Check if vasopressin is coded under different concept")
            else:
                logger.info("\n1. Vasopressin: â Data found")
        
        # Check FiO2
        fio2_result = None
        for cat_results in results.values():
            for r in cat_results:
                if r['concept_id'] == 3013468:
                    fio2_result = r
                    break
        
        if fio2_result and fio2_result['record_count'] == 0:
            logger.warning("\n2. FiO2: No data found")
            logger.warning("   - Respiratory SOFA will be NULL for most patients")
            logger.warning("   - This is CORRECT (no imputation), but reduces sample size")
        
        logger.info("\nâ Validation complete")


def main():
    parser = argparse.ArgumentParser(
        description='Validate OMOP site for SOFA calculation'
    )
    parser.add_argument('--connection-string', required=True,
                       help='Database connection string (postgresql://user:pass@host/db)')
    parser.add_argument('--cdm-schema', default='cdm',
                       help='CDM schema name (default: cdm)')
    parser.add_argument('--vocab-schema', default='vocab',
                       help='Vocabulary schema name (default: vocab)')
    
    args = parser.parse_args()
    
    validator = ConceptValidator(
        args.connection_string,
        args.cdm_schema,
        args.vocab_schema
    )
    
    if not validator.connect():
        sys.exit(1)
    
    results = validator.validate_all()
    validator.print_summary(results)
    
    # Exit with error if critical concepts missing
    critical_missing = any(
        not r['exists'] or r['descendants'] == 0
        for cat_results in results.values()
        for r in cat_results
        if r.get('critical')
    )
    
    sys.exit(1 if critical_missing else 0)


if __name__ == '__main__':
    main()
