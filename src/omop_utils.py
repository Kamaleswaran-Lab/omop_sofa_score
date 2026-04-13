import pandas as pd
import numpy as np
from typing import List

def expand_concepts(concept_ids: List[int], concept_ancestor_df: pd.DataFrame) -> List[int]:
    if concept_ancestor_df is None or concept_ancestor_df.empty:
        return concept_ids
    descendants = concept_ancestor_df[
        concept_ancestor_df['ancestor_concept_id'].isin(concept_ids)
    ]['descendant_concept_id'].unique().tolist()
    return list(set(concept_ids + descendants))

def convert_creatinine(value, from_unit):
    if from_unit in ['umol/L', 'micromole per liter']:
        return value / 88.4
    return value

def convert_bilirubin(value, from_unit):
    if from_unit in ['umol/L', 'micromole per liter']:
        return value / 17.1
    return value

def convert_pao2(value, from_unit):
    if from_unit in ['kPa', 'kilopascal']:
        return value * 7.50062
    return value

def normalize_fio2(value):
    if value > 1.0:
        return value / 100.0
    return value
