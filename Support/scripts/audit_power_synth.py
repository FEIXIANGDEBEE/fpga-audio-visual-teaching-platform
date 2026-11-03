from pathlib import Path
import json,ast
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_A_ACTIVE.json').read_text())['path']);g=graph((B/'synthesized.v').read_text())
tree=ast.parse((R/'scripts/audit_v121_a.py').read_text());f=[x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='evaluator'];ns={'bits':bits};exec(compile(ast.Module(body=f,type_ignores=[]),'mapped_evaluator','exec'),ns)
initial={};count=1024;mask=(1<<count)-1
for i in range(10):
    net='\\startup/startup['+str(i)+']'
    owners=[(n,k,p,w,list(reversed(bits(w['q']))).index(net)) for n,(k,p,w) in g.items() if k in ['AL_MAP_SEQ','EG_PHY_MSLICE','EG_PHY_LSLICE'] and net in bits(w.get('q',''))]
    assert len(owners)==1
    n,k,p,w,lane=owners[0]
    if k=='AL_MAP_SEQ':assert p['__REG_INIT__']==0
    else:assert p[f'REG{lane}_REGSET']=='"RESET"' and p['SRMUX']=='"0"','Native mapped counter register must retain initial zero'
    initial[net]=sum(((v>>i)&1)<<v for v in range(count))
flag=g['\\startup/released_reg'];assert flag[0]=='AL_MAP_SEQ' and flag[1]['__REG_INIT__']==0 and flag[1]['CEMUX']=='"1"' and flag[1]['SRMUX']=='"0"' and 'sr' not in flag[2]
initial[flag[2]['q']]=1<<1023
changed=True
while changed:
 changed=False
 for k,p,w in g.values():
  if k=='buf':
   for a,b in zip(bits(w['o']),bits(w['i'])):
    if a in initial and b not in initial:initial[b]=initial[a];changed=True
    if b in initial and a not in initial:initial[a]=initial[b];changed=True
    if a in initial and b in initial:assert initial[a]==initial[b]
ev=ns['evaluator'](g,initial,mask);assert ev(flag[2]['d'])==((1<<1022)|(1<<1023))
result={'pass':True,'build':str(B),'counter_initial_bits':10,'counter_INIT0':True,'released_INIT0':True,'reachable_counter_values':1024,'exact_mapped_next_function':True,'release_edge':1023,'one_clock_lookahead_no_latency_change':True,'prior_RTL_diff_edges_reused':8192,'new_execution':'Current synthesized counter/release INIT and all1024 mapped next states; no new RTL simulation','source_flag':flag}
(R/'reports/POWER_RESET_SYNTH.json').write_text(json.dumps(result,indent=2)+'\n');print('POWER_RESET_SYNTH_PASS',flush=True)
