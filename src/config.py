
import yaml, os
class Config:
    def __init__(self, path):
        with open(path) as f:
            self.cfg = yaml.safe_load(f)
        for k,v in self.cfg['database'].items():
            if isinstance(v,str) and v.startswith("${"):
                env = v[2:-1]
                self.cfg['database'][k] = os.getenv(env)
    def get(self, key, default=None):
        return self.cfg.get(key, default)
