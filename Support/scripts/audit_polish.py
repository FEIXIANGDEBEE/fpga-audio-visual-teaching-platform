"""Actual new A pending-operation identity and its retained physical registers."""
from pathlib import Path
import json,sys,re
from scene_mapped_graph import graph,bits
r=Path(__file__).resolve().parents[1];b=Path(json.loads((r/'reports/BUILD_A_ACTIVE.json').read_text())['path']);phase=sys.argv[1]
g=graph((b/(phase+'.v')).read_text());rows=[]
if phase=='synthesized':
 names=['\\controls/user_pending_reg']+[f'\\controls/pending_op_reg[{i}]' for i in range(5)]
 for n in names:
  k,p,w=g[n];assert k=='AL_MAP_SEQ' and re.fullmatch(r'sys_clk_dup_\d+',w['clk']) and p['__REG_INIT__']==0,(n,k,p,w)
  rows.append({'register':n,'Q':w['q'],'clock':w['clk']})
else:
 old=json.loads((r/'reports/POLISH_SYNTHESIZED.json').read_text());alias={}
 for k,p,w in g.values():
  if k=='buf':
   for o,i in zip(bits(w['o']),bits(w['i'])):alias[o]=i
 def root(x):
  seen=set()
  while x in alias:assert x not in seen;seen.add(x);x=alias[x]
  return x
 for row in old['registers']:
  q=root(row['Q']);drivers=[(n,k) for n,(k,p,w) in g.items() if k!='buf' and q in [root(x) for x in bits(w.get('q',''))]]
  assert len(drivers)==1 and drivers[0][1] in ['EG_PHY_MSLICE','EG_PHY_LSLICE'],(q,drivers)
  rows.append({'Q':q,'physical_register':drivers[0][0],'clock_intent':row['clock']})
v={'pass':True,'phase':phase,'build':str(b),'user_pending_bits':1,'pending_op_bits':5,'registers':rows,'scope':'Retained pending-operation register identity in the actual V15 A object','behavioral_proof':'V15 R1 menu tests and TARGETED_TESTS.json; unchanged legacy behavior reused','actual_B':'V15 B separately synthesized and signed off; see OFFLINE_SIGNOFF_B.json'}
(r/f'reports/POLISH_{phase.upper()}.json').write_text(json.dumps(v,indent=2)+'\n');print('POLISH_NATIVE_PASS',phase,flush=True)
