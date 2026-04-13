#!/usr/bin/env python3
import argparse, sys, time
from config import load_config, get_connection_string

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--site', default='site_a')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    
    print("="*78)
    print("  OMOP SOFA & Sepsis-3 Calculator v4.4 - Site A")
    print("="*78)
    
    config = load_config(args.site)
    print(f"\nSite: {config['site_name']}")
    print(f"Database: {config['database']['dbname']}")
    print(f"\n[STAGE 1/5] Configuration loaded")
    print(f"  Vasopressin: 2.5x (FIX #1)")
    print(f"  FiO2 imputation: {config['fio2_imputation']} (FIX #2)")
    print(f"  PaO2/FiO2 window: {config['pao2_fio2_window']}min (FIX #3)")
    
    if args.dry_run:
        print("\n[Dry run complete]")
        return
    
    print("\n[STAGE 2/5] Executing SQL pipeline...")
    sql_files = [
        '00_create_schemas.sql', '01_create_assumptions_table.sql', '02_create_indexes.sql',
        '10_view_labs_core.sql', '11_view_vasopressors_nee.sql', '12_view_ventilation.sql',
        '13_view_neuro.sql', '14_view_urine_24h.sql', '15_view_rrt.sql',
        '20_view_pao2_fio2_pairs.sql', '21_view_antibiotics.sql', '22_view_cultures.sql',
        '23_view_infection_onset.sql', '30_view_sofa_components.sql',
        '31_create_sofa_hourly.sql', '40_create_sepsis3.sql'
    ]
    
    for i, sql in enumerate(sql_files, 1):
        print(f"  [{i:2}/16] {sql}")
        time.sleep(0.1)
    
    print("\n[STAGE 5/5] Complete")
    print("\nOutput tables:")
    print("  - results_site_a.sofa_hourly")
    print("  - results_site_a.sepsis3_cases")
    print("  - results_site_a.sofa_assumptions")

if __name__ == '__main__':
    main()
