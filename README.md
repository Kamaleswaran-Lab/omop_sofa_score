# OMOP SOFA Score v4.4 COMPLETE

Self-contained repository with all 16 SQL files.

## Files
- sql/00-02: Setup
- sql/10-15: Core views (labs, vasopressors, ventilation, neuro, urine, RRT)
- sql/20-23: PaO2/FiO2, antibiotics, cultures, infection
- sql/30-31: SOFA components and hourly
- sql/40: Sepsis-3

## All 10 flaws fixed
1. Vasopressin included
2. No FiO2 imputation
3. 240-min window
4. GCS RASS nulling
5. Pre-infection baseline
6. 24h urine + RRT
