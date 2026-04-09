from omop_utils import *
from omop_calc_sofa import compute_daily_sofa
from omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

# load your CDM dict and concept_ancestor
daily_sofa = compute_daily_sofa(cdm, cdm_ancestor)
suspected = compute_suspected_infection(cdm, cdm_ancestor)
sepsis3 = evaluate_sepsis3(daily_sofa, suspected, cdm, cdm_ancestor)
