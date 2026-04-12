"""
src/validate_concepts.py - Run at site onboarding to check ETL quality
Reports % of labs captured by ancestor vs hardcoded fallback
"""

import pandas as pd
from omop_utils import fetch, sql_concept_set, HARDCODED, CLINICAL_SCHEMA, VOCAB_SCHEMA

def validate_site(conn, sample_n=10000):
    """Returns DataFrame with coverage per lab domain"""
    results = []
    for domain, codes in HARDCODED.items():
        # Ancestor count
        sql_anc = f"""
        SELECT COUNT(DISTINCT measurement_id) as n
        FROM {CLINICAL_SCHEMA}.measurement m
        WHERE m.measurement_concept_id IN ({sql_concept_set(domain)})
        LIMIT {sample_n}
        """
        # Hardcoded count
        ids = ",".join(map(str, codes))
        sql_hard = f"""
        SELECT COUNT(DISTINCT measurement_id) as n
        FROM {CLINICAL_SCHEMA}.measurement m
        WHERE m.measurement_concept_id IN ({ids})
        LIMIT {sample_n}
        """
        # Total with either
        sql_both = f"""
        SELECT COUNT(DISTINCT measurement_id) as n
        FROM {CLINICAL_SCHEMA}.measurement m
        WHERE m.measurement_concept_id IN ({sql_concept_set(domain)}) OR m.measurement_concept_id IN ({ids})
        LIMIT {sample_n}
        """
        try:
            n_anc = fetch(conn, sql_anc).iloc[0,0]
            n_hard = fetch(conn, sql_hard).iloc[0,0]
            n_both = fetch(conn, sql_both).iloc[0,0]
            results.append({
                'domain': domain,
                'ancestor_only': n_anc,
                'hardcoded_only': max(0, n_hard - n_anc),
                'both': n_anc,
                'total_captured': n_both,
                'pct_from_hardcoded': round(100 * max(0, n_both - n_anc) / max(1, n_both), 1)
            })
        except Exception as e:
            results.append({'domain': domain, 'error': str(e)})
    
    df = pd.DataFrame(results)
    print("\n=== CONCEPT COVERAGE REPORT ===")
    print(df.to_string(index=False))
    print("\nRecommendation: If pct_from_hardcoded >20%, keep CONCEPT_MODE='hybrid'")
    return df

if __name__ == "__main__":
    import psycopg2
    conn = psycopg2.connect(dbname="mgh", user="postgres")
    validate_site(conn)
