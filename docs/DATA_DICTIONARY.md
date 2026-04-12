# DATA_DICTIONARY.md

## sofa_hourly table

| Column | Type | Description |
|--------|------|-------------|
| person_id | bigint | OMOP person_id |
| visit_occurrence_id | bigint | ICU visit |
| charttime | timestamp | Hour timestamp |
| total | float | Total SOFA (0-24) |
| resp | int | Respiratory SOFA 0-4 |
| cardio | int | Cardiovascular SOFA 0-4 |
| neuro | int | Neurologic SOFA 0-4 |
| hepatic | int | Hepatic SOFA 0-4 |
| renal | int | Renal SOFA 0-4 |
| coag | int | Coagulation SOFA 0-4 |
| pf | float | PaO2/FiO2 ratio |
| sf_eq | float | SpO2/FiO2 equivalent PF |
| ne | float | Norepinephrine equivalent ug/kg/min |
| ne_src | text | Rate derivation method |

## sofa_assumptions table

| Column | Description |
|--------|-------------|
| fio2_imputed | True if FiO2 was imputed |
| fio2_imputation_method | 'vent_carryforward', 'vent_assumed_60', 'room_air_21' |
| vaso_rate_source | 'direct', 'weight_adjusted', 'quantity_duration_weight', 'quantity_duration_70kg' |
| vaso_assumed_weight | True if 70kg assumed |
| baseline_source | 'min_72_6', 'last_24_1', 'imputed_zero', 'chronic_disease' |
