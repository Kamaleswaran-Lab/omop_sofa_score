import pandas as pd
import numpy as np
import re

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

def normalize_cdm(cdm):
    for standard_name, df in cdm.items():
        df.columns = [c.lower() for c in df.columns]
        if standard_name == 'drug_exposure':
            if 'dose_unit_concept_id' not in df.columns:
                df['dose_unit_concept_id'] = np.nan
            if 'quantity' in df.columns and 'sig' in df.columns:
                sig_numeric = pd.to_numeric(df['sig'], errors='coerce')
                df['quantity'] = df['quantity'].fillna(sig_numeric)
                still_missing = df['quantity'].isna() & df['sig'].notna()
                if still_missing.any():
                    extracted = df.loc[still_missing, 'sig'].astype(str).str.extract(r'([0-9]*\.?[0-9]+)')[0]
                    df.loc[still_missing, 'quantity'] = pd.to_numeric(extracted, errors='coerce')
        for col in df.columns:
            if 'date' in col or 'time' in col:
                df[col] = pd.to_datetime(df[col], errors='coerce', utc=True).dt.tz_localize(None)
        for id_col in ['person_id', 'visit_occurrence_id']:
            if id_col in df.columns:
                df[id_col] = pd.to_numeric(df[id_col], errors='coerce').astype('Int64')
        cdm[standard_name] = df
    return cdm

def expand_concepts(ancestor_df, seed_ids):
    if ancestor_df is None or ancestor_df.empty:
        return list(set(seed_ids))
    if 'ancestor_concept_id' in ancestor_df.columns:
        ancestor_df.columns = [c.lower() for c in ancestor_df.columns]
    ancestor_df['ancestor_concept_id'] = pd.to_numeric(ancestor_df['ancestor_concept_id'], errors='coerce')
    ancestor_df['descendant_concept_id'] = pd.to_numeric(ancestor_df['descendant_concept_id'], errors='coerce')
    mask = ancestor_df['ancestor_concept_id'].isin(seed_ids)
    descendants = ancestor_df.loc[mask, 'descendant_concept_id'].dropna().unique().tolist()
    return list(set(seed_ids + descendants))

def get_vasopressors(cdm, ancestor_df=None):
    seeds = []
    for k in ['norepinephrine','epinephrine','dopamine','dobutamine','phenylephrine','vasopressin']:
        seeds.extend(CONCEPT_SEEDS[k])
    drug_ids = expand_concepts(ancestor_df, seeds)
    de = cdm['drug_exposure']
    v = de[de['drug_concept_id'].isin(drug_ids)].copy()
    if v.empty:
        return pd.DataFrame()
    
    for col in ['quantity','dose_unit_concept_id','route_concept_id','drug_exposure_end_datetime','sig']:
        if col not in v.columns:
            v[col] = np.nan
    
    v = v[['person_id','visit_occurrence_id','drug_exposure_start_datetime','drug_exposure_end_datetime','quantity','dose_unit_concept_id','route_concept_id','drug_concept_id','sig']]
    v = v.rename(columns={'drug_exposure_start_datetime':'start','drug_exposure_end_datetime':'end'})
    v['start'] = pd.to_datetime(v['start'])
    v['end'] = pd.to_datetime(v['end'].fillna(v['start'] + pd.Timedelta(hours=1)))
    v['person_id'] = pd.to_numeric(v['person_id'], errors='coerce').astype('Int64')
    v['visit_occurrence_id'] = pd.to_numeric(v['visit_occurrence_id'], errors='coerce').astype('Int64')
    
    weight = cdm['measurement']
    weight = weight[weight['measurement_concept_id'].isin([3025315, 3013762])]
    weight = weight[['person_id','measurement_datetime','value_as_number']].rename(columns={'measurement_datetime':'wt_time','value_as_number':'weight_kg'})
    weight['person_id'] = pd.to_numeric(weight['person_id'], errors='coerce').astype('Int64')
    weight['wt_time'] = pd.to_datetime(weight['wt_time'], errors='coerce')
    
    if not weight.empty:
        v = pd.merge_asof(v.sort_values('start'), weight.sort_values('wt_time'), by='person_id', left_on='start', right_on='wt_time', direction='backward', tolerance=pd.Timedelta('24h'))
    else:
        v['weight_kg'] = 70
    
    v['duration_hr'] = (v['end'] - v['start']).dt.total_seconds()/3600
    v['duration_hr'] = v['duration_hr'].replace(0, 1)
    
    has_qty = v['quantity'].notna() & (v['quantity'] > 0)
    v['rate_mcg_per_min'] = np.nan
    v.loc[has_qty, 'rate_mcg_per_min'] = v.loc[has_qty, 'quantity'] * 1000 / (v.loc[has_qty, 'duration_hr'] * 60)
    v['rate_mcg_kg_min'] = v['rate_mcg_per_min'] / v['weight_kg'].fillna(70)
    v['on_vaso'] = 1
    
    if has_qty.any():
        print(f"Rescued {has_qty.sum()} vasopressor doses from SIG column")
    
    if (~has_qty).any():
        missing = v[~has_qty].copy()
        print(f"\nWARNING: {len(missing)} vasopressor records still missing QUANTITY after SIG rescue.")
        print("--- First 5 problematic records ---")
        cols_to_show = ['person_id','drug_concept_id','start','end','quantity','sig','duration_hr']
        cols_to_show = [c for c in cols_to_show if c in missing.columns]
        print(missing[cols_to_show].head(5).to_string(index=False))
        print("\n--- SIG value examples ---")
        if 'sig' in missing.columns:
            print(missing['sig'].dropna().head(10).tolist())
    
    return v

# Keep other functions minimal for this debug version
def get_measurements(cdm, seed_keys, domain=None, ancestor_df=None):
    return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','unit_concept_id'])

def derive_map(cdm, ancestor_df=None):
    return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','source'])

def derive_gcs(cdm, ancestor_df=None):
    return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','source'])

def get_paired_pao2_fio2(cdm, ancestor_df=None):
    return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','pao2','fio2','pfratio'])

def get_urine_output_24h(cdm, ancestor_df=None):
    return pd.DataFrame(columns=['person_id','visit_occurrence_id','chartdate','uo_24h_ml'])

def get_cultures(cdm, ancestor_df=None):
    return pd.DataFrame()

def get_antibiotics(cdm, ancestor_df=None):
    return pd.DataFrame()
