"""Only the three preauthorized, isolated physical lanes. No hardware."""
from pathlib import Path
import json,subprocess,sys,time
R=Path(__file__).resolve().parents[1]
C=Path('D:/aidownload/anlu_main/main1/V15_1_low_power')
jobs=[]
for seed in (3,5,7):
    assert not (C/f'route_b_seed{seed}').exists()
    log=(C/f'lane_seed{seed}.log').open('w')
    p=subprocess.Popen([sys.executable,'-u','-B',str(R/'scripts/lane_b.py'),str(seed)],cwd=R,stdout=log,stderr=subprocess.STDOUT)
    jobs.append((seed,p,log));print('START',seed,p.pid,flush=True)
(C/'LANE_RUNNERS.json').write_text(json.dumps([dict(seed=s,pid=p.pid) for s,p,l in jobs],indent=2))
while any(p.poll() is None for s,p,l in jobs):
    time.sleep(2)
for s,p,l in jobs:
    l.close();print('EXIT',s,p.returncode,flush=True)
