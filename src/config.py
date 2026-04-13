import os
import yaml
from pathlib import Path

def load_config(site_name=None):
    if site_name is None:
        site_name = os.getenv('OMOP_SITE', 'site_a')
    
    config_path = Path(__file__).parent.parent / 'config' / f'{site_name}.yaml'
    
    if not config_path.exists():
        raise FileNotFoundError(f"Config not found: {config_path}")
    
    with open(config_path) as f:
        config = yaml.safe_load(f)
    
    if 'password' in config['database']:
        pwd = config['database']['password']
        if pwd.startswith('${') and pwd.endswith('}'):
            env_var = pwd[2:-1]
            config['database']['password'] = os.getenv(env_var, '')
    
    return config

def get_connection_string(config):
    db = config['database']
    return f"postgresql://{db['user']}:{db['password']}@{db['host']}:{db['port']}/{db['dbname']}"
