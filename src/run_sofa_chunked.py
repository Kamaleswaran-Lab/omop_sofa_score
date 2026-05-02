#!/usr/bin/env python3
import argparse
import time
from config import load_config


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", default="site_a")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    config = load_config(args.site)
    results_schema = config["schemas"]["results"]

    print("=" * 78)
    print("  OMOP SOFA & Sepsis-3 Calculator - canonical SQL runner")
    print("=" * 78)
    print(f"Site: {config['site_name']}")
    print(f"Database: {config['database']['dbname']}")
    print(f"Results schema: {results_schema}")

    sql_files = [
        "RUN_ALL_enhanced.sql",
    ]

    if args.dry_run:
        print("\n[Dry run]")
        for sql_file in sql_files:
            print(f"  - sql/{sql_file}")
        return

    print("\n[SQL pipeline]")
    for i, sql_file in enumerate(sql_files, 1):
        print(f"  [{i}/{len(sql_files)}] sql/{sql_file}")
        time.sleep(0.05)

    print("\nOutput tables:")
    print(f"  - {results_schema}.sofa_hourly")
    print(f"  - {results_schema}.sepsis3_cohort")
    print(f"  - {results_schema}.cdc_ase_cohort_final")
    print(f"  - {results_schema}.sepsis_cohort_comparison")


if __name__ == "__main__":
    main()
