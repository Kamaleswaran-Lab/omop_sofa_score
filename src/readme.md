from omop_calc_sofa import compute_omop_sofa
from omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

# 1. Generate longitudinal organ failure scores
longitudinal_sofa = compute_omop_sofa(cdm, cdm_ancestor)

# 2. Identify clinical infection windows
t_inf_cohort = compute_suspected_infection(cdm, cdm_ancestor)

# 3. Apply Sepsis-3 phenotype constraints
final_sepsis3_cohort = evaluate_sepsis3(longitudinal_sofa, t_inf_cohort)
