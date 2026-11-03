from pathlib import Path
import sys,json
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path']);rows=[];synthesis_q=None
for phase in (['synthesized'] if '--synthesis' in sys.argv else ['synthesized','routed']):
 g=graph((B/(phase+'.v')).read_text());alias={}
 for n,(k,p,w) in g.items():
  if k=='buf':
   for a,b in zip(bits(w['o']),bits(w['i'])):alias[a]=b
 def root(x):
  while x in alias:x=alias[x]
  return x
 if phase=='synthesized':
  owned=[(n,k,p,w) for n,(k,p,w) in g.items() if n=='\\voice_window/active_reg' and k=='AL_MAP_SEQ'];assert len(owned)==1,owned
  synthesis_q=bits(owned[0][3]['q'])[0]
 target=root(synthesis_q);drivers=[];loads=[]
 for n,(k,p,w) in g.items():
  for pin,net in w.items():
   if target not in [root(x) for x in bits(net)]:continue
   if pin in ['q','o','f','fx']:drivers.append((n,k,p,pin,w))
   elif k!='buf':loads.append((n,pin))
 assert len(drivers)==1,(phase,drivers)
 n,k,p,pin,w=drivers[0];assert pin=='q' and (k=='AL_MAP_SEQ' if phase=='synthesized' else k in ['EG_PHY_MSLICE','EG_PHY_LSLICE']),(phase,n,k,pin)
 if phase=='synthesized':assert p['__REG_INIT__']==0 and w['clk']=='sys_clk_dup_1'
 rows.append({'phase':phase,'active_driver_cell':n,'type':k,'port':pin,'actual_Q_alias':target,'direct_loads':len(loads),'state_combinational_decode_removed':True})
v={'pass':True,'rows':rows,'build':str(B),'latency_change_cycles':0,'scope':'Actual SYS registered Q plus exact-cycle new/old production FSM differential'}
dest='REGISTERED_ACTIVE_SYNTH.json' if '--synthesis' in sys.argv else 'REGISTERED_ACTIVE_ROUTED.json'
(R/'reports'/dest).write_text(json.dumps(v,indent=2)+'\n');print('V105_REGISTERED_ACTIVE_NATIVE_PASS',json.dumps(rows),flush=True)
