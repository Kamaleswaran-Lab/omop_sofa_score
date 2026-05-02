-- 03b_siteA_expansion.sql
-- Site-specific additions only - run AFTER 03_create_concept_sets.sql
INSERT INTO :results_schema.concept_set_members VALUES
('fio2', 3024882, NULL, true, false, 'CUSTOM', 'O2 Total gas [VF] Ventilator'),
('ventilation', 2147482986, 'Procedure', true, false, 'CUSTOM', 'MV ETT Double Lumen'),
('ventilation', 2147482987, 'Procedure', true, false, 'CUSTOM', 'MV ETT Comment'),
('ecmo', 46257397, 'Procedure', true, false, 'CUSTOM', 'ECMO <6y'),
('ecmo', 46257398, 'Procedure', true, false, 'CUSTOM', 'ECMO 6y+')
ON CONFLICT DO NOTHING;
