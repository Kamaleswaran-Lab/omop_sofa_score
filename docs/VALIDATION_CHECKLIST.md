# Validation Checklist v4.1
1. Run sql/01-03 to create schemas
2. Run sql/10-15 for labs, drugs, vent, neuro, urine, RRT
3. Run sql/20-22 for antibiotics and cultures
4. Verify vasopressin appears in v_vasopressors with nee_factor=2.5
5. Verify v_lab fio2 has no imputed 0.6 values
6. Check PaO2/FiO2 pairs have delta_min <=240
7. Check neuro: patients with RASS<=-4 have gcs NULL
8. Check renal: patients on RRT have score 4
9. Check infection_onset joins abx+culture within 72h
10. Compare 50 chart-reviewed SOFA scores
