
from config import Config
from omop_utils import get_engine, CONCEPT_SETS, descendant_concepts
import sys
cfg=Config('config/site_template.yaml'); eng=get_engine(cfg.cfg)
with eng.connect() as c:
    for name,anc in CONCEPT_SETS.items():
        ids=descendant_concepts(c, cfg.get('schemas')['vocabulary'], anc)
        cnt=c.execute(f"SELECT COUNT(*) FROM {cfg.get('schemas')['clinical']}.measurement WHERE measurement_concept_id = ANY(ARRAY{ids})").scalar()
        print(f"{name}: {len(ids)} descendants, {cnt} rows")
