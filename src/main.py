import psycopg2
from src.omop_utils import set_schemas, set_verbose
from src.omop_calc_sofa import compute_daily_sofa, compute_hourly_sofa
from src.omop_calc_sepsis3 import compute_suspected_infection, evaluate_sepsis3

set_schemas(clinical="omopcdm", vocab="vocabulary")
set_verbose(True)

conn = psycopg2.connect(dbname="mgh", user="...", host="...", password="...")

# hourly then daily (matches README API)
hourly = compute_hourly_sofa(db_conn=conn, person_ids=[1907]) # or None for all
daily = compute_daily_sofa(db_conn=conn, person_ids=[1907])

# sepsis-3
suspected = compute_suspected_infection(db_conn=conn, person_ids=[1907])
sepsis3 = evaluate_sepsis3(hourly, suspected)
