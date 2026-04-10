import pandas as pd
import numpy as np

# -------------------------------------------------------------------------
# SOFA / Sepsis-3 Concept Seeds - expand via concept_ancestor in production
# -------------------------------------------------------------------------
CONCEPT_SEEDS = {
    'platelets': [3007461, 3024929],
    'bilirubin_total': [3024128],
    'creatinine': [3016723, 3020564, 3022243],
    'map_direct': [3027598, 21492239],
    'sbp': [3013295, 3033276],
    'dbp': [3013502, 3033275],
    'gcs_total': [3032652, 41101853],
    'gcs_eye': [3013823],
    'gcs_verbal': [3005263],
    'gcs_motor': [3006237],
    'pao2': [3012731],
    'fio2': [3016502, 3023541],
    'spo2': [3012672, 3020411],
    'urine_output': [3013466, 3013940, 21490854, 4061863],
    'norepinephrine': [1343916],
    'epinephrine': [1321341],
    'dopamine': [1337860],
    'dobutamine': [1337720],
    'phenylephrine': [1507835],
    'vasopressin': [11149],
    'antibiotics_systemic': [1738622, 1713332, 1717327, 1707164],
    'culture_procedure': [4046279],
    'mech_vent': [4052536, 4233974, 4302208],
    'rrt_procedure': [4146536, 4149391, 4048662]
}

UNIT_MAP = {
    'creatinine': {8840: 1.0, 8554: 1/88.4},
    'bilirubin': {8840: 1.0, 8554: 1/17.1},
    'pao2': {8645: 1.0, 8753: 7.50062},
    'platelets': {8847: 1.0, 8848: 1.0},
    'fio2': {8554: 0.01, 8713: 0.01, 0: 1.0}
}

def expand_concepts(ancestor_df, seed_ids):
    if ancestor_df is None or ancestor_df.empty:
        return list(set(seed_ids))
    mask = ancestor_df['ancestor_concept_id'].isin(seed_ids)
    descendants = ancestor_df.loc[mask, 'descendant_concept_id'].unique().tolist()
    return list(set(seed_ids + descendants))

def convert_units(df, value_col, unit_col, domain):
    if df.empty or domain not in UNIT_MAP:
        return df
    df = df.copy()
    conv = df[unit_col].map(UNIT_MAP[domain]).fillna(1.0)
    if domain == 'fio2':
        df[value_col] = np.where(df[value_col] > 1.5, df[value_col] * 0.01, df[value_col])
    df[value_col] = df[value_col] * conv
    return df

def get_measurements(cdm, seed_keys, domain=None, ancestor_df=None):
    seeds = []
    for k in seed_keys:
        seeds.extend(CONCEPT_SEEDS.get(k, []))
    concept_ids = expand_concepts(ancestor_df, seeds)
    m = cdm['measurement']
    df = m[m['measurement_concept_id'].isin(concept_ids)].copy()
    if df.empty:
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value'])
    df = df[['person_id','visit_occurrence_id','measurement_datetime','value_as_number','unit_concept_id']]
    df = df.rename(columns={'measurement_datetime':'charttime','value_as_number':'value'})
    df['charttime'] = pd.to_datetime(df['charttime'])
    if domain:
        df = convert_units(df, 'value', 'unit_concept_id', domain)
    return df[['person_id','visit_occurrence_id','charttime','value']].dropna(subset=['value'])

def derive_map(cdm, ancestor_df=None):
    direct = get_measurements(cdm, ['map_direct'], domain=None, ancestor_df=ancestor_df)
    direct['source'] = 'direct'
    sbp = get_measurements(cdm, ['sbp'], ancestor_df=ancestor_df).rename(columns={'value':'sbp'})
    dbp = get_measurements(cdm, ['dbp'], ancestor_df=ancestor_df).rename(columns={'value':'dbp'})
    bp = pd.merge_asof(
        sbp.sort_values('charttime'),
        dbp.sort_values('charttime'),
        by=['person_id','visit_occurrence_id'],
        on='charttime',
        direction='nearest',
        tolerance=pd.Timedelta('5min')
    )
    bp = bp.dropna(subset=['sbp','dbp'])
    bp['value'] = (bp['sbp'] + 2*bp['dbp'])/3
    bp['source'] = 'derived'
    derived = bp[['person_id','visit_occurrence_id','charttime','value','source']]
    return pd.concat([direct, derived], ignore_index=True)

def derive_gcs(cdm, ancestor_df=None):
    total = get_measurements(cdm, ['gcs_total'], ancestor_df=ancestor_df)
    total['source'] = 'total'
    eye = get_measurements(cdm, ['gcs_eye'], ancestor_df=ancestor_df).rename(columns={'value':'eye'})
    verb = get_measurements(cdm, ['gcs_verbal'], ancestor_df=ancestor_df).rename(columns={'value':'verbal'})
    motor = get_measurements(cdm, ['gcs_motor'], ancestor_df=ancestor_df).rename(columns={'value':'motor'})
    comp = eye.merge(verb, on=['person_id','visit_occurrence_id','charttime'], how='inner')
    comp = comp.merge(motor, on=['person_id','visit_occurrence_id','charttime'], how='inner')
    comp['value'] = comp['eye'] + comp['verbal'] + comp['motor']
    comp['source'] = 'components'
    comp = comp[['person_id','visit_occurrence_id','charttime','value','source']]
    return pd.concat([total, comp], ignore_index=True)

def get_paired_pao2_fio2(cdm, ancestor_df=None):
    pao2 = get_measurements(cdm, ['pao2'], domain='pao2', ancestor_df=ancestor_df).rename(columns={'value':'pao2'})
    fio2 = get_measurements(cdm, ['fio2'], domain='fio2', ancestor_df=ancestor_df).rename(columns={'value':'fio2'})
    pao2 = pao2.sort_values('charttime')
    fio2 = fio2.sort_values('charttime')
    paired = pd.merge_asof(
        pao2, fio2,
        by=['person_id','visit_occurrence_id'],
        on='charttime',
        direction='nearest',
        tolerance=pd.Timedelta('60min')
    )
    paired = paired.dropna(subset=['pao2','fio2'])
    paired = paired[paired['fio2'] >= 0.21]
    paired['pfratio'] = paired['pao2'] / paired['fio2']
    return paired[['person_id','visit_occurrence_id','charttime','pao2','fio2','pfratio']]

def get_urine_output_24h(cdm, ancestor_df=None):
    uo = get_measurements(cdm, ['urine_output'], ancestor_df=ancestor_df)
    if uo.empty:
        return uo
    uo['chartdate'] = pd.to_datetime(uo['charttime']).dt.floor('D')
    daily = uo.groupby(['person_id','visit_occurrence_id','chartdate'])['value'].sum().reset_index()
    return daily.rename(columns={'value':'uo_24h_ml'})

def get_vasopressors(cdm, ancestor_df=None):
    seeds = []
    for k in ['norepinephrine','epinephrine','dopamine','dobutamine','phenylephrine','vasopressin']:
        seeds.extend(CONCEPT_SEEDS[k])
    drug_ids = expand_concepts(ancestor_df, seeds)
    de = cdm['drug_exposure']
    v = de[de['drug_concept_id'].isin(drug_ids)].copy()
    if v.empty:
        return pd.DataFrame()
    v = v[['person_id','visit_occurrence_id','drug_exposure_start_datetime','drug_exposure_end_datetime','quantity','dose_unit_concept_id','route_concept_id','drug_concept_id']]
    v = v.rename(columns={'drug_exposure_start_datetime':'start','drug_exposure_end_datetime':'end'})
    v['start'] = pd.to_datetime(v['start'])
    v['end'] = pd.to_datetime(v['end'])
    weight = cdm['measurement']
    weight = weight[weight['measurement_concept_id'].isin([3025315, 3013762])]
    weight = weight[['person_id','measurement_datetime','value_as_number']].rename(columns={'measurement_datetime':'wt_time','value_as_number':'weight_kg'})
    weight['wt_time'] = pd.to_datetime(weight['wt_time'])
    v = pd.merge_asof(v.sort_values('start'), weight.sort_values('wt_time'), by='person_id', left_on='start', right_on='wt_time', direction='backward', tolerance=pd.Timedelta('24h'))
    v['duration_hr'] = (pd.to_datetime(v['end']) - pd.to_datetime(v['start'])).dt.total_seconds()/3600
    v['rate_mcg_per_min'] = np.where(v['duration_hr']>0, v['quantity']*1000 / (v['duration_hr']*60), np.nan)
    v['rate_mcg_kg_min'] = v['rate_mcg_per_min'] / v['weight_kg']
    return v

def get_cultures(cdm, ancestor_df=None):
    proc_ids = expand_concepts(ancestor_df, CONCEPT_SEEDS['culture_procedure'])
    po = cdm.get('procedure_occurrence', pd.DataFrame())
    cultures = pd.DataFrame()
    if not po.empty:
        cultures = po[po['procedure_concept_id'].isin(proc_ids)][['person_id','visit_occurrence_id','procedure_datetime']].rename(columns={'procedure_datetime':'culture_time'})
    spec = cdm.get('specimen', pd.DataFrame())
    if not spec.empty:
        s = spec[['person_id','visit_occurrence_id','specimen_datetime']].rename(columns={'specimen_datetime':'culture_time'})
        cultures = pd.concat([cultures, s], ignore_index=True)
    cultures['culture_time'] = pd.to_datetime(cultures['culture_time'])
    return cultures.drop_duplicates()

def get_antibiotics(cdm, ancestor_df=None):
    abx_ids = expand_concepts(ancestor_df, CONCEPT_SEEDS['antibiotics_systemic'])
    de = cdm['drug_exposure']
    abx = de[de['drug_concept_id'].isin(abx_ids)].copy()
    systemic_routes = [4128794, 4132161, 4136135]
    abx = abx[abx['route_concept_id'].isin(systemic_routes) | abx['route_concept_id'].isna()]
    abx = abx[['person_id','visit_occurrence_id','drug_exposure_start_datetime']].rename(columns={'drug_exposure_start_datetime':'abx_time'})
    abx['abx_time'] = pd.to_datetime(abx['abx_time'])
    return abx.drop_duplicates()
