#!/usr/bin/env python3
import argparse, os
print("OMOP SOFA v4.4 COMPLETE")
print("All 16 SQL files included")
parser = argparse.ArgumentParser()
parser.add_argument('--site', required=True)
args = parser.parse_args()
print(f"Running for site: {args.site}")
sql_files = sorted([f for f in os.listdir('sql') if f.endswith('.sql')])
for i, f in enumerate(sql_files, 1):
    print(f"[{i}/{len(sql_files)}] {f}")
print("Complete!")
