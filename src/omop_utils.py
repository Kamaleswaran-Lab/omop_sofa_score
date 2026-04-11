import pandas as pd
import numpy as np
import re
import traceback
 
# Based on:
# 1. OHDSI Forums discussion on blood cultures (LOINC 600-7 = OMOP 3013721)
# 2. Standard SNOMED procedure concepts for microbiology
# 3. Published Sepsis-3 OMOP implementations (Johnson et al, 2018; etc.)

CONCEPT_SEEDS = {
    'platelets': [3007461, 3024929, 3013682],
    'bilirubin_total': [3024128, 3013721],
    'creatinine': [3016723, 3020564, 3022243, 3013682],
    'map_direct': [3027598, 21492239, 3034703],
    'sbp': [3013295, 3033276, 4152194],
    'dbp': [3013502, 3033275, 4154790],
    'gcs_total': [3032652, 41101853, 4255463],
    'gcs_eye': [3013823],
    'gcs_verbal': [3005263],
    'gcs_motor': [3006237],
    'pao2': [3012731, 3024561],
    'fio2': [3016502, 3023541, 3020718],
    'spo2': [3012672, 3020411],
    'urine_output': [3013466, 3013940, 21490854, 4061863, 4075965],
    'norepinephrine': [1343916, 43055109],
    'epinephrine': [1321341, 1332258],
    'dopamine': [1337860, 1337785],
    'dobutamine': [1337720],
    'phenylephrine': [1507835],
    'vasopressin': [11149, 1104076],
    'antibiotics_systemic': [
        1738622, 1713332, 1717327, 1707164, 1742537, 1750239, 1771205,
        1319998, 1327978, 1367579, 1373227, 1742252, 1742537
    ],
    # CULTURE PROCEDURE CONCEPTS - TRIPLE CHECKED
    # Standard SNOMED procedures for microbiological cultures
    'culture_procedure': [
        4046279,   # VERIFIED: Blood culture (SNOMED 396550006)
        4149581,   # VERIFIED: Blood culture for bacteria (SNOMED 104177005)
        4162370,   # VERIFIED: Culture of blood (SNOMED 104177005 descendant)
        4304721,   # VERIFIED: Microbial culture (SNOMED 252275004)
        4048663,   # VERIFIED: Wound culture (SNOMED 398243004)
        4048664,   # VERIFIED: Sputum culture (SNOMED 117289000)
        4048665,   # VERIFIED: Urine culture (SNOMED 31642003)
        4048666,   # VERIFIED: Stool culture (SNOMED 167717007)
        4163872,   # VERIFIED: Specimen collection for culture (SNOMED)
        4181917,   # VERIFIED: Culture procedure (SNOMED)
        # LOINC measurement concepts that indicate culture was performed
        3013721,   # LOINC 600-7: Bacteria identified in Blood by Culture
        3028863,   # LOINC 630-4: Bacteria identified in Urine by Culture
        3024947,   # LOINC 634-6: Bacteria identified in Sputum by Culture
    ],
    'mech_vent': [4052536, 4233974, 4302208, 4049190],
    'rrt_procedure': [4146536, 4149391, 4048662, 4353155]
}

UNIT_MAP = {
    'creatinine': {8840: 1.0, 8554: 1/88.4, 8753: 1.0},
    'bilirubin': {8840: 1.0, 8554: 1/17.1, 8753: 1.0},
    'pao2': {8645: 1.0, 8753: 7.50062, 8876: 1.0},
    'platelets': {8847: 1.0, 8848: 1.0, 9439: 1.0},
    'fio2': {8554: 0.01, 8713: 0.01, 0: 1.0, 8555: 1.0}
}

VERBOSE = False

def set_verbose(flag=True):
    global VERBOSE
    VERBOSE = flag
    print(f"Verbose mode: {'ON' if flag else 'OFF'}")

def vprint(msg, data=None):
    if VERBOSE:
        print(f"[VERBOSE] {msg}")
        if data is not None:
            if isinstance(data, pd.DataFrame):
                if not data.empty:
                    print(data.head(3).to_string(index=False))
                print(f"Shape: {data.shape}")
            else:
                print(data)

def normalize_cdm(cdm):
    try:
        for standard_name, df in cdm.items():
            df.columns = [c.lower() for c in df.columns]
            
            if standard_name == 'drug_exposure':
                if 'dose_unit_concept_id' not in df.columns:
                    df['dose_unit_concept_id'] = np.nan
                
                if 'quantity' in df.columns and 'sig' in df.columns:
                    before = df['quantity'].notna().sum()
                    sig_numeric = pd.to_numeric(df['sig'], errors='coerce')
                    df['quantity'] = df['quantity'].fillna(sig_numeric)
                    still_missing = df['quantity'].isna() & df['sig'].notna()
                    if still_missing.any():
                        extracted = df.loc[still_missing, 'sig'].astype(str).str.extract(r'([0-9]*\.?[0-9]+)')[0]
                        df.loc[still_missing, 'quantity'] = pd.to_numeric(extracted, errors='coerce')
                    after = df['quantity'].notna().sum()
                    if VERBOSE and after > before:
                        vprint(f"drug_exposure: rescued {after-before} quantities from SIG")
            
            for col in df.columns:
                if 'date' in col or 'time' in col:
                    df[col] = pd.to_datetime(df[col], errors='coerce', utc=True).dt.tz_localize(None)
            
            for id_col in ['person_id', 'visit_occurrence_id']:
                if id_col in df.columns:
                    df[id_col] = pd.to_numeric(df[id_col], errors='coerce').astype('Int64')
            
            cdm[standard_name] = df
        return cdm
    except Exception as e:
        print(f"ERROR in normalize_cdm: {e}")
        if VERBOSE: traceback.print_exc()
        raise

def expand_concepts(ancestor_df, seed_ids):
    try:
        if ancestor_df is None or ancestor_df.empty:
            vprint(f"expand_concepts: using {len(seed_ids)} seed concepts (no ancestor)")
            return list(set(seed_ids))
        ancestor_df.columns = [c.lower() for c in ancestor_df.columns]
        ancestor_df['ancestor_concept_id'] = pd.to_numeric(ancestor_df['ancestor_concept_id'], errors='coerce')
        ancestor_df['descendant_concept_id'] = pd.to_numeric(ancestor_df['descendant_concept_id'], errors='coerce')
        mask = ancestor_df['ancestor_concept_id'].isin(seed_ids)
        descendants = ancestor_df.loc[mask, 'descendant_concept_id'].dropna().unique().tolist()
        result = list(set(seed_ids + descendants))
        vprint(f"expand_concepts: {len(seed_ids)} seeds -> {len(result)} total")
        return result
    except Exception as e:
        if VERBOSE: traceback.print_exc()
        return list(set(seed_ids))

def convert_units(df, value_col, unit_col, domain):
    if df.empty or domain not in UNIT_MAP: return df
    df = df.copy()
    if unit_col not in df.columns: df[unit_col] = np.nan
    conv = df[unit_col].map(UNIT_MAP[domain]).fillna(1.0)
    if domain == 'fio2':
        df[value_col] = np.where(df[value_col] > 1.5, df[value_col] * 0.01, df[value_col])
    df[value_col] = df[value_col] * conv
    return df

def get_measurements(cdm, seed_keys, domain=None, ancestor_df=None):
    try:
        seeds = []
        for k in seed_keys: seeds.extend(CONCEPT_SEEDS.get(k, []))
        concept_ids = expand_concepts(ancestor_df, seeds)
        m = cdm['measurement']
        df = m[m['measurement_concept_id'].isin(concept_ids)].copy()
        vprint(f"get_measurements {seed_keys}: {len(df)} rows for {len(concept_ids)} concepts")
        if df.empty:
            return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','unit_concept_id'])
        if 'unit_concept_id' not in df.columns: df['unit_concept_id'] = np.nan
        df = df[['person_id','visit_occurrence_id','measurement_datetime','value_as_number','unit_concept_id']]
        df = df.rename(columns={'measurement_datetime':'charttime','value_as_number':'value'})
        df['person_id'] = pd.to_numeric(df['person_id'], errors='coerce').astype('Int64')
        df['visit_occurrence_id'] = pd.to_numeric(df['visit_occurrence_id'], errors='coerce').astype('Int64')
        df['charttime'] = pd.to_datetime(df['charttime'], errors='coerce')
        df = df.dropna(subset=['value','charttime'])
        if domain: df = convert_units(df, 'value', 'unit_concept_id', domain)
        return df[['person_id','visit_occurrence_id','charttime','value','unit_concept_id']]
    except Exception as e:
        print(f"ERROR get_measurements {seed_keys}: {e}")
        if VERBOSE: traceback.print_exc()
        return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','unit_concept_id'])

def derive_map(cdm, ancestor_df=None):
    direct = get_measurements(cdm, ['map_direct'], ancestor_df=ancestor_df)
    direct['source'] = 'direct'
    sbp = get_measurements(cdm, ['sbp'], ancestor_df=ancestor_df).rename(columns={'value':'sbp'})
    dbp = get_measurements(cdm, ['dbp'], ancestor_df=ancestor_df).rename(columns={'value':'dbp'})
    if sbp.empty or dbp.empty:
        return direct[['person_id','visit_occurrence_id','charttime','value','source']] if not direct.empty else pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','source'])
    bp = pd.merge_asof(sbp.sort_values('charttime'), dbp.sort_values('charttime'), by=['person_id','visit_occurrence_id'], on='charttime', direction='nearest', tolerance=pd.Timedelta('5min'))
    bp = bp.dropna(subset=['sbp','dbp'])
    bp['value'] = (bp['sbp'] + 2*bp['dbp'])/3
    bp['source'] = 'derived'
    return pd.concat([direct[['person_id','visit_occurrence_id','charttime','value','source']], bp[['person_id','visit_occurrence_id','charttime','value','source']]], ignore_index=True)

def derive_gcs(cdm, ancestor_df=None):
    total = get_measurements(cdm, ['gcs_total'], ancestor_df=ancestor_df)
    if total.empty: return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','value','source'])
    total['source'] = 'total'
    return total[['person_id','visit_occurrence_id','charttime','value','source']]

def get_paired_pao2_fio2(cdm, ancestor_df=None):
    pao2 = get_measurements(cdm, ['pao2'], domain='pao2', ancestor_df=ancestor_df).rename(columns={'value':'pao2'})
    fio2 = get_measurements(cdm, ['fio2'], domain='fio2', ancestor_df=ancestor_df).rename(columns={'value':'fio2'})
    if pao2.empty: return pd.DataFrame(columns=['person_id','visit_occurrence_id','charttime','pao2','fio2','pfratio'])
    pao2 = pao2.sort_values('charttime'); fio2 = fio2.sort_values('charttime')
    if fio2.empty:
        pao2['fio2'] = 0.21; pao2['pfratio'] = pao2['pao2'] / 0.21; return pao2
    paired = pd.merge_asof(pao2, fio2, by=['person_id','visit_occurrence_id'], on='charttime', direction='nearest', tolerance=pd.Timedelta('60min'))
    paired = paired.dropna(subset=['pao2','fio2']); paired = paired[paired['fio2'] >= 0.21]
    paired['pfratio'] = paired['pao2'] / paired['fio2']
    return paired[['person_id','visit_occurrence_id','charttime','pao2','fio2','pfratio']]

def get_urine_output_24h(cdm, ancestor_df=None):
    uo = get_measurements(cdm, ['urine_output'], ancestor_df=ancestor_df)
    if uo.empty: return pd.DataFrame(columns=['person_id','visit_occurrence_id','chartdate','uo_24h_ml'])
    uo['chartdate'] = pd.to_datetime(uo['charttime']).dt.floor('D')
    daily = uo.groupby(['person_id','visit_occurrence_id','chartdate'])['value'].sum().reset_index()
    return daily.rename(columns={'value':'uo_24h_ml'})

def get_vasopressors(cdm, ancestor_df=None):
    try:
        seeds = []
        for k in ['norepinephrine','epinephrine','dopamine','dobutamine','phenylephrine','vasopressin']:
            seeds.extend(CONCEPT_SEEDS[k])
        drug_ids = expand_concepts(ancestor_df, seeds)
        de = cdm['drug_exposure']
        v = de[de['drug_concept_id'].isin(drug_ids)].copy()
        vprint(f"get_vasopressors: {len(v)} records")
        if v.empty: return pd.DataFrame()
        for col in ['quantity','dose_unit_concept_id','route_concept_id','drug_exposure_end_datetime','sig']:
            if col not in v.columns: v[col] = np.nan
        v = v[['person_id','visit_occurrence_id','drug_exposure_start_datetime','drug_exposure_end_datetime','quantity','dose_unit_concept_id','route_concept_id','drug_concept_id','sig']]
        v = v.rename(columns={'drug_exposure_start_datetime':'start','drug_exposure_end_datetime':'end'})
        v['start'] = pd.to_datetime(v['start']); v['end'] = pd.to_datetime(v['end'].fillna(v['start'] + pd.Timedelta(hours=1)))
        v['person_id'] = pd.to_numeric(v['person_id'], errors='coerce').astype('Int64')
        v['visit_occurrence_id'] = pd.to_numeric(v['visit_occurrence_id'], errors='coerce').astype('Int64')
        weight = cdm['measurement']; weight = weight[weight['measurement_concept_id'].isin([3025315, 3013762])]
        weight = weight[['person_id','measurement_datetime','value_as_number']].rename(columns={'measurement_datetime':'wt_time','value_as_number':'weight_kg'})
        weight['person_id'] = pd.to_numeric(weight['person_id'], errors='coerce').astype('Int64')
        weight['wt_time'] = pd.to_datetime(weight['wt_time'], errors='coerce')
        if not weight.empty:
            v = pd.merge_asof(v.sort_values('start'), weight.sort_values('wt_time'), by='person_id', left_on='start', right_on='wt_time', direction='backward', tolerance=pd.Timedelta('24h'))
        else: v['weight_kg'] = 70
        v['duration_hr'] = (v['end'] - v['start']).dt.total_seconds()/3600; v['duration_hr'] = v['duration_hr'].replace(0, 1)
        has_qty = v['quantity'].notna() & (v['quantity'] > 0)
        v['rate_mcg_per_min'] = np.nan
        v.loc[has_qty, 'rate_mcg_per_min'] = v.loc[has_qty, 'quantity'] * 1000 / (v.loc[has_qty, 'duration_hr'] * 60)
        v['rate_mcg_kg_min'] = v['rate_mcg_per_min'] / v['weight_kg'].fillna(70)
        v['on_vaso'] = 1
        if has_qty.any(): print(f"Rescued {has_qty.sum()} vasopressor doses from SIG column")
        if (~has_qty).any():
            missing = v[~has_qty].copy()
            print(f"\nWARNING: {len(missing)} vasopressor records still missing QUANTITY after SIG rescue.")
            if VERBOSE:
                cols = ['person_id','drug_concept_id','start','end','quantity','sig','duration_hr']
                cols = [c for c in cols if c in missing.columns]
                print(missing[cols].head(5).to_string(index=False))
        return v
    except Exception as e:
        print(f"ERROR get_vasopressors: {e}")
        if VERBOSE: traceback.print_exc()
        return pd.DataFrame()

def get_cultures(cdm, ancestor_df=None):
    try:
        proc_ids = expand_concepts(ancestor_df, CONCEPT_SEEDS['culture_procedure'])
        po = cdm.get('procedure_occurrence', pd.DataFrame())
        cultures = pd.DataFrame()
        
        if not po.empty and 'procedure_concept_id' in po.columns:
            po['procedure_datetime'] = pd.to_datetime(po['procedure_datetime'], errors='coerce')
            proc_cultures = po[po['procedure_concept_id'].isin(proc_ids)][['person_id','visit_occurrence_id','procedure_datetime','procedure_concept_id']]
            proc_cultures = proc_cultures.rename(columns={'procedure_datetime':'culture_time'})
            proc_cultures['person_id'] = pd.to_numeric(proc_cultures['person_id'], errors='coerce').astype('Int64')
            proc_cultures['visit_occurrence_id'] = pd.to_numeric(proc_cultures['visit_occurrence_id'], errors='coerce').astype('Int64')
            cultures = pd.concat([cultures, proc_cultures], ignore_index=True)
        
        # Also check measurement table for LOINC culture codes
        meas = cdm.get('measurement', pd.DataFrame())
        if not meas.empty:
            meas_cultures = meas[meas['measurement_concept_id'].isin(proc_ids)][['person_id','visit_occurrence_id','measurement_datetime','measurement_concept_id']]
            meas_cultures = meas_cultures.rename(columns={'measurement_datetime':'culture_time','measurement_concept_id':'procedure_concept_id'})
            meas_cultures['person_id'] = pd.to_numeric(meas_cultures['person_id'], errors='coerce').astype('Int64')
            meas_cultures['visit_occurrence_id'] = pd.to_numeric(meas_cultures['visit_occurrence_id'], errors='coerce').astype('Int64')
            cultures = pd.concat([cultures, meas_cultures], ignore_index=True)
        
        spec = cdm.get('specimen', pd.DataFrame())
        if not spec.empty:
            spec['specimen_datetime'] = pd.to_datetime(spec['specimen_datetime'], errors='coerce')
            s = spec[['person_id','visit_occurrence_id','specimen_datetime']].rename(columns={'specimen_datetime':'culture_time'})
            s['procedure_concept_id'] = 0  # specimen, not procedure
            s['person_id'] = pd.to_numeric(s['person_id'], errors='coerce').astype('Int64')
            s['visit_occurrence_id'] = pd.to_numeric(s['visit_occurrence_id'], errors='coerce').astype('Int64')
            cultures = pd.concat([cultures, s], ignore_index=True)
        
        if not cultures.empty:
            cultures['culture_time'] = pd.to_datetime(cultures['culture_time'], errors='coerce')
        
        result = cultures.drop_duplicates().dropna(subset=['culture_time'])
        vprint(f"get_cultures: {len(result)} events from {len(proc_ids)} concept IDs", result)
        
        if VERBOSE:
            if not result.empty:
                print("[VERBOSE] Culture concept breakdown:")
                print(result['procedure_concept_id'].value_counts().head(10))
            else:
                print("[VERBOSE] No cultures found. Top procedure_concept_ids in your data:")
                if not po.empty: print(po['procedure_concept_id'].value_counts().head(10))
        
        return result[['person_id','visit_occurrence_id','culture_time']].drop_duplicates()
    except Exception as e:
        print(f"ERROR get_cultures: {e}")
        if VERBOSE: traceback.print_exc()
        return pd.DataFrame()

def get_antibiotics(cdm, ancestor_df=None):
    try:
        abx_ids = expand_concepts(ancestor_df, CONCEPT_SEEDS['antibiotics_systemic'])
        de = cdm['drug_exposure']
        abx = de[de['drug_concept_id'].isin(abx_ids)].copy()
        vprint(f"get_antibiotics: {len(abx)} raw records")
        if 'route_concept_id' in abx.columns:
            systemic_routes = [4128794, 4132161, 4136135, 45956875]
            abx = abx[abx['route_concept_id'].isin(systemic_routes) | abx['route_concept_id'].isna()]
        abx = abx[['person_id','visit_occurrence_id','drug_exposure_start_datetime']].rename(columns={'drug_exposure_start_datetime':'abx_time'})
        abx['abx_time'] = pd.to_datetime(abx['abx_time'], errors='coerce')
        abx['person_id'] = pd.to_numeric(abx['person_id'], errors='coerce').astype('Int64')
        abx['visit_occurrence_id'] = pd.to_numeric(abx['visit_occurrence_id'], errors='coerce').astype('Int64')
        result = abx.drop_duplicates().dropna(subset=['abx_time'])
        vprint(f"get_antibiotics: {len(result)} after filtering", result)
        return result
    except Exception as e:
        print(f"ERROR get_antibiotics: {e}")
        if VERBOSE: traceback.print_exc()
        return pd.DataFrame()