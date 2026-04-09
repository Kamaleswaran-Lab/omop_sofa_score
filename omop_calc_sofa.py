import pandas as pd
import numpy as np

def compute_omop_sofa(cdm):
    """
    Computes the ICU SOFA score based on standard OHDSI/OMOP vocabularies.
    """
    # -------------------------------------------------------------------------
    # 1. Verified OMOP Concept IDs 
    # (LOINC for Labs/Vitals, RxNorm for active Vasopressor ingredients)
    # -------------------------------------------------------------------------
    concepts = {
        'platelets': [3007461, 3024929],           # Platelets [#/volume] in Blood (Manual & Auto)
        'bilirubin': [3024128],                    # Bilirubin.total [Mass/volume] in Serum or Plasma
        'creatinine': [3016723, 3020564, 3022243], # Creatinine in Serum or Plasma (incl. pre-dialysis)
        'map': [3027598],                          # Mean blood pressure
        'gcs': [3032652],                          # Glasgow coma scale
        'pao2': [3012731],                         # Oxygen [Partial pressure] in Arterial blood
        'fio2': [3016502],                         # Oxygen [Volume Fraction] of inhaled gas
        'urine_output': [3013466, 3013940],        # Urine output 24 hour / Volume of Urine
        
        'vasopressors': [
            1321341, # Norepinephrine
            1343916, # Epinephrine
            1337860, # Dopamine
            1337720  # Dobutamine
        ]
    }

    # Helper function to extract specific concepts from the measurement table
    def get_measurements(concept_list, col_name):
        # Filter for the correct standard concepts
        df = cdm['measurement'][cdm['measurement']['measurement_concept_id'].isin(concept_list)].copy()
        df = df[['person_id', 'visit_occurrence_id', 'measurement_datetime', 'value_as_number']]
        df = df.rename(columns={'value_as_number': col_name, 'measurement_datetime': 'charttime'})
        return df

    # -------------------------------------------------------------------------
    # 2. Build the target DataFrames (simulating I2_Sepsis modular logic)
    # -------------------------------------------------------------------------
    
    # -- LVDF (Labs and Vitals) --
    plt_df = get_measurements(concepts['platelets'], 'platelets')
    bili_df = get_measurements(concepts['bilirubin'], 'bilirubin')
    creat_df = get_measurements(concepts['creatinine'], 'creatinine')
    map_df = get_measurements(concepts['map'], 'map')
    gcs_df = get_measurements(concepts['gcs'], 'gcs')
    pao2_df = get_measurements(concepts['pao2'], 'pao2')
    fio2_df = get_measurements(concepts['fio2'], 'fio2')

    # Merge LVDF components onto a unified timeline per patient/visit
    lvdf = pd.concat([plt_df, bili_df, creat_df, map_df, gcs_df, pao2_df, fio2_df], ignore_index=True)
    lvdf['charttime'] = pd.to_datetime(lvdf['charttime'])
    
    # Group by Date to get the worst 24-hour values for SOFA scoring
    lvdf['chartdate'] = lvdf['charttime'].dt.date
    daily_lvdf = lvdf.groupby(['person_id', 'visit_occurrence_id', 'chartdate']).agg(
        min_platelets=('platelets', 'min'),
        max_bilirubin=('bilirubin', 'max'),
        max_creatinine=('creatinine', 'max'),
        min_map=('map', 'min'),
        min_gcs=('gcs', 'min'),
        min_pao2=('pao2', 'min'),
        max_fio2=('fio2', 'max') 
    ).reset_index()

    # Calculate PaO2/FiO2 ratio (Ensuring FiO2 is represented as a fraction <= 1.0)
    daily_lvdf['max_fio2'] = np.where(daily_lvdf['max_fio2'] > 1.0, daily_lvdf['max_fio2'] / 100.0, daily_lvdf['max_fio2'])
    daily_lvdf['pf_ratio'] = np.where(daily_lvdf['max_fio2'] > 0, 
                                      daily_lvdf['min_pao2'] / daily_lvdf['max_fio2'], 
                                      np.nan)

    # -- VASODF (Vasopressors) --
    vaso = cdm['drug_exposure'][cdm['drug_exposure']['drug_concept_id'].isin(concepts['vasopressors'])].copy()
    vaso['chartdate'] = pd.to_datetime(vaso['drug_exposure_start_date']).dt.date
    vaso['vaso_active'] = 1
    daily_vaso = vaso.groupby(['person_id', 'visit_occurrence_id', 'chartdate'])['vaso_active'].max().reset_index()

    # -- UODF (Urine Output) --
    uo_df = get_measurements(concepts['urine_output'], 'urine_output')
    uo_df['chartdate'] = uo_df['charttime'].dt.date
    daily_uo = uo_df.groupby(['person_id', 'visit_occurrence_id', 'chartdate'])['urine_output'].sum().reset_index()

    # -------------------------------------------------------------------------
    # 3. Merge everything into a master daily dataframe
    # -------------------------------------------------------------------------
    daily_sofa = daily_lvdf.merge(daily_vaso, on=['person_id', 'visit_occurrence_id', 'chartdate'], how='left')
    daily_sofa = daily_sofa.merge(daily_uo, on=['person_id', 'visit_occurrence_id', 'chartdate'], how='left')
    daily_sofa['vaso_active'] = daily_sofa['vaso_active'].fillna(0)
    
    # -------------------------------------------------------------------------
    # 4. Calculate SOFA Sub-scores (0 to 4)
    # -------------------------------------------------------------------------
    
    def score_resp(row):
        pf = row['pf_ratio']
        if pd.isna(pf): return 0
        if pf < 100: return 4
        if pf < 200: return 3
        if pf < 300: return 2
        if pf < 400: return 1
        return 0

    def score_coag(row):
        plt = row['min_platelets']
        if pd.isna(plt): return 0
        if plt < 20: return 4
        if plt < 50: return 3
        if plt < 100: return 2
        if plt < 150: return 1
        return 0

    def score_liver(row):
        bili = row['max_bilirubin']
        if pd.isna(bili): return 0
        if bili >= 12.0: return 4
        if bili >= 6.0: return 3
        if bili >= 2.0: return 2
        if bili >= 1.2: return 1
        return 0

    def score_cv(row):
        map_val = row['min_map']
        vaso = row['vaso_active']
        if vaso == 1: return 3 # Binary fallback for vasopressor administration
        if pd.isna(map_val): return 0
        if map_val < 70: return 1
        return 0

    def score_cns(row):
        gcs = row['min_gcs']
        if pd.isna(gcs): return 0
        if gcs < 6: return 4
        if gcs <= 9: return 3
        if gcs <= 12: return 2
        if gcs <= 14: return 1
        return 0

    def score_renal(row):
        cr = row['max_creatinine']
        uo = row['urine_output']
        
        cr_score = 0
        if not pd.isna(cr):
            if cr >= 5.0: cr_score = 4
            elif cr >= 3.5: cr_score = 3
            elif cr >= 2.0: cr_score = 2
            elif cr >= 1.2: cr_score = 1
            
        uo_score = 0
        if not pd.isna(uo):
            if uo < 200: uo_score = 4
            elif uo < 500: uo_score = 3
            
        return max(cr_score, uo_score)

    # Apply scoring
    daily_sofa['sofa_respiration'] = daily_sofa.apply(score_resp, axis=1)
    daily_sofa['sofa_coagulation'] = daily_sofa.apply(score_coag, axis=1)
    daily_sofa['sofa_liver']     = daily_sofa.apply(score_liver, axis=1)
    daily_sofa['sofa_cardiovascular'] = daily_sofa.apply(score_cv, axis=1)
    daily_sofa['sofa_cns']       = daily_sofa.apply(score_cns, axis=1)
    daily_sofa['sofa_renal']     = daily_sofa.apply(score_renal, axis=1)

    # Total Daily SOFA
    daily_sofa['total_sofa'] = (
        daily_sofa['sofa_respiration'] + 
        daily_sofa['sofa_coagulation'] + 
        daily_sofa['sofa_liver'] + 
        daily_sofa['sofa_cardiovascular'] + 
        daily_sofa['sofa_cns'] + 
        daily_sofa['sofa_renal']
    )
    
    return daily_sofa

# Run the calculation
sofa_df = compute_omop_sofa(cdm)
