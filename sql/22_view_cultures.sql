DROP VIEW IF EXISTS results_site_a.vw_cultures CASCADE;

CREATE OR REPLACE VIEW results_site_a.vw_cultures AS
SELECT 
    m.person_id,
    m.measurement_datetime AS specimen_datetime,
    m.measurement_concept_id AS specimen_concept_id,
    c.concept_name AS specimen_name
FROM omopcdm.measurement m
LEFT JOIN vocabulary.concept c ON m.measurement_concept_id = c.concept_id
WHERE m.measurement_concept_id IN (
    3023368, 3013867, 3026008, 3025099, 3039355,
    40762243, 3003714, 3000494, 3005702, 3025941,
    3011298, 3016727, 3027005, 3016114, 3037692,
    3016914, 3023419, 3015479, 3045330, 40765191,
    3010254, 3006761, 3002619, 3019902, 3044495,
    3009986, 3004840, 3017611, 3006119, 3023601,
    3018069, 3023207, 3024461, 3028433, 3015409,
    3036000, 43533857, 3046974, 3024572, 3026870,
    3025468, 3007234, 3012568, 3045873, 3009171,
    3005988, 3012475, 3034171, 3014856, 3011175
);
