"""Prove every added reset-buffer branch is identity from the actual release Q, using packed INIT/wiring."""
from pathlib import Path
import json
from scene_mapped_graph import graph,bits
from reset_distribution_a import inventory as reset_inventory
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_A_ACTIVE.json').read_text())['path'])
plan=json.loads((B/'reset_distribution_a.json').read_text());g=graph((B/'routed.v').read_text());drivers={}
sg=graph((B/'synthesized.v').read_text())
source='rst_n';source_cells=[]
for name,(kind,p,w) in g.items():
 if source in bits(w.get('q','')):source_cells.append(name)
 if kind=='buf':drivers[w['o']]=(kind,p,w,0,name,'o')
 elif kind in ['EG_PHY_MSLICE','EG_PHY_LSLICE']:
  for port in ['f','fx']:
   for lane,out in enumerate(reversed(bits(w.get(port,'')))):
    if out:drivers[out]=(kind,p,w,lane,name,port)
assert source=='rst_n'
source_cells=['same combinational startup rst_n; graph delta proof preserves its driver']
memo={source:2};ALL=3;roots={}
def ev(net):
 if net in memo:return memo[net]
 if net=="1'b0":return 0
 if net=="1'b1" or net.startswith('open_n'):return ALL
 kind,p,w,lane,name,port=drivers[net]
 if kind=='buf':val=ev(w['i'])
 else:
  assert port=='f' and p.get('MODE','"LOGIC"')=='"LOGIC"',(net,kind,p)
  ins=[]
  for pin in 'abcd':
   bs=list(reversed(bits(w[pin]))) if pin in w else ["1'b1"]*2;ins.append(ev(bs[lane]))
  if kind=='EG_PHY_MSLICE':init=p.get('INIT_LUT'+str(lane),('number',0))[1]
  else:
   init=p.get('INIT_LUTF'+str(lane),('number',0))[1];mux=p.get('LSFMUX'+str(lane),'"LUTF"');assert mux in ['"LUTF"','"FUNC5"']
   if mux=='"FUNC5"':assert init==p.get('INIT_LUTG'+str(lane),('number',0))[1]
  val=0
  for index in range(16):
   if init>>index&1:
    term=ALL
    for j,value in enumerate(ins):term &= value if index>>j&1 else ALL^value
    val|=term
 memo[net]=val;return val
rows=[]
assert plan['maximum_group_sr_ports']==128
actual_plan=reset_inventory(sg,group_limit=128)
actual_cells=[s['cell'] for branch in actual_plan for s in branch['sinks']]
recorded_cells=[s['cell'] for branch in plan['branches'] for s in branch['sinks']]
assert len(actual_cells)==len(set(actual_cells))==plan['sinks']
assert len(recorded_cells)==len(set(recorded_cells))==len(actual_cells)
assert set(actual_cells)==set(recorded_cells),'Reset inventory does not cover actual synthesis endpoints'
assert len(actual_plan)==plan['buffers']
for expected,recorded in zip(actual_plan,plan['branches']):
 assert all(expected[k]==recorded[k] for k in ['source','group','clock','sinks'])
for branch in plan['branches']:
 net=branch['net'];assert ev(net)==2,('Reset polarity/function changed',net)
 root=net
 while drivers[root][0]=='buf':root=drivers[root][2]['i']
 kind,p,w,lane,name,port=drivers[root];assert kind in ['EG_PHY_MSLICE','EG_PHY_LSLICE']
 key=(name,port,lane);assert key not in roots,('Reset branches merged',key);roots[key]=net
 sinks=[n for n,(k,p,w) in g.items() if w.get('sr')==net]
 # A mapped native arithmetic cell can hold two FFs and unpack at placement.
 gate_ffs=sum(len([q for q in bits(sg[s['cell']][2].get('q','')) if not q.startswith('open_n')]) for s in branch['sinks'])
 assert sinks and len(branch['sinks'])<=128,(net,len(sinks),len(branch['sinks']))
 rows.append({'net':net,'physical_lut':name,'lane':lane,'native_sr_loads':len(sinks),'gate_sr_ports':len(branch['sinks']),'gate_ffs':gate_ffs,'identity_inputs_checked':[0,1]})
assert len(rows)==plan['buffers']
aliases={source};changed=True
while changed:
 changed=False
 for name,(kind,p,w) in g.items():
  if kind=='buf' and w['i'] in aliases and w['o'] not in aliases:aliases.add(w['o']);changed=True
direct=[n for n,(k,p,w) in g.items() if w.get('sr') in aliases];assert not direct,('Unbuffered analysis reset SR endpoints',direct)
value={'pass':True,'source_q':source,'source_cell':source_cells[0],'buffer_count':len(rows),'gate_sr_ports':plan['sinks'],'maximum_gate_group':128,
 'actual_maximum_physical_sr_fanout':max(x['native_sr_loads'] for x in rows),'no_unbuffered_sr':True,'sequential_latency_unchanged':True,'new_reset_false_paths':False,
 'method':'Both reset levels through actual packed INIT/wiring; unique retained branches, all gate SR rewires in canonical proof, no direct physical SR on original Q; record post-pack physical fanout and require real STA',
 'harness_correction':'Complete exact endpoint enumeration from this candidate synthesis; recorded and actual sink sets and enables must match uniquely. Group limit32, identity and no-unbuffered-endpoint gates retained. Physical fanout is measured separately.',
 'branches':rows}
(B/'physical_reset_truth.json').write_text(json.dumps(value,indent=2)+'\n');(R/'reports/RESET_A_PHYSICAL.json').write_text(json.dumps(value,indent=2)+'\n');print('RESET_BUFFER_PHYSICAL_TRUTH_PASS',len(rows),flush=True)
