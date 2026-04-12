
from sqlalchemy import create_engine, text
CONCEPT_SETS = {
 'pao2': 3002647, 'fio2': 3013468, 'creatinine': 3016723,
 'bilirubin': 3024128, 'platelets': 3013290, 'gcs': 4253928,
 'rass': 40488434, 'urine': 4065485, 'rrt': 4146536,
 'vent_device': 45768131, 'vent_proc': 4302207
}
def get_engine(cfg):
    db = cfg['database']
    return create_engine(f"postgresql://{db['user']}:{db['password']}@{db['host']}:{db['port']}/{db['dbname']}", pool_size=5)
def descendant_concepts(conn, vocab_schema, ancestor_id):
    sql = text(f"SELECT descendant_concept_id FROM {vocab_schema}.concept_ancestor WHERE ancestor_concept_id=:a")
    return [r[0] for r in conn.execute(sql, {'a': ancestor_id})]
def get_measurements(conn, clinical_schema, person_ids, concept_ids, start, end):
    ids = ','.join(map(str, concept_ids))
    sql = f"SELECT person_id, measurement_concept_id, measurement_datetime, value_as_number, unit_concept_id FROM {clinical_schema}.measurement WHERE person_id IN ({','.join(map(str,person_ids))}) AND measurement_concept_id IN ({ids}) AND measurement_datetime BETWEEN '{start}' AND '{end}'"
    return conn.execute(text(sql)).fetchall()
