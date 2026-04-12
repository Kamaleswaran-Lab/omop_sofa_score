from sqlalchemy import create_engine

def get_engine(cfg):
 db=cfg['database']; return create_engine(f"postgresql://{db['user']}:{db['password']}@{db['host']}:{db['port']}/{db['dbname']}")
