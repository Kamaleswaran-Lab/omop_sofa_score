
import argparse
from config import Config
from omop_utils import get_engine
def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--site',required=True); a=parser.parse_args()
    cfg=Config(f'config/{a.site}.yaml'); eng=get_engine(cfg.cfg)
    with eng.begin() as c:
        for sql in sorted([f for f in __import__('os').listdir('sql') if f.endswith('.sql')]):
            print(f"Running {sql}"); c.exec_driver_sql(open(f'sql/{sql}').read())
    print("v4.1 full pipeline built: vasopressin included, FiO2 not imputed, 240min window, RASS nulling, pre-infection baseline")
if __name__=='__main__': main()
