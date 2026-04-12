import yaml,os
class Config:
 def __init__(self,p):
  self.cfg=yaml.safe_load(open(p))
 def get(self,k): return self.cfg.get(k)
