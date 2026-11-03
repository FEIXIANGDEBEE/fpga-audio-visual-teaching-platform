"""Release witness: exact retained progress counter, no debug CRC/window cone."""
from pathlib import Path
import sys,json
from scene_mapped_graph import graph,bits
r=Path(__file__).resolve().parents[1];b=Path(json.loads((r/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
phase='synthesized' if '--synthesis' in sys.argv else 'routed';g=graph((b/(phase+'.v')).read_text())
prefix='\\replay_counter/witness/'
for component in ['crc_reg','held_reg','window_id_reg','window_crc_reg','base_frame_reg','count_reg','overruns_reg']:
 assert not [n for n in g if n.startswith(prefix+component)],component+' debug cone retained'
rows=[]
if phase=='synthesized':
 for group,clock,width in [('replay_counter/witness/total_frames','audio_mclk_dup_1',32),('replay_counter/snapshot/held_data','audio_mclk_dup_1',32),('replay_counter/snapshot/snapshot','sys_clk_dup_1',32)]:
  cells=[(n,w) for n,(k,p,w) in g.items() if k=='AL_MAP_SEQ' and n.startswith('\\'+group+'_reg[')]
  assert len(cells)==width,(group,len(cells))
  assert all(w['clk']==clock for n,w in cells),(group,clock)
  rows += [{'register':n,'Q':w['q'],'clock':w['clk']} for n,w in cells]
else:
 old=json.loads((r/'reports/WITNESS_SYNTH.json').read_text());aliases={}
 for k,p,w in g.values():
  if k=='buf':
   for o,i in zip(bits(w['o']),bits(w['i'])):aliases[o]=i
 def root(n):
  seen=set()
  while n in aliases:assert n not in seen;seen.add(n);n=aliases[n]
  return n
 for row in old['registers']:
  q=root(row['Q']);found=[]
  for n,(k,p,w) in g.items():
   if k!='buf' and q in [root(x) for x in bits(w.get('q',''))]:found.append((n,k))
  assert len(found)==1 and found[0][1] in ['EG_PHY_MSLICE','EG_PHY_LSLICE'],(q,found)
  rows.append({'Q':q,'physical_register':found[0][0],'clock_intent':row['clock']})
v={'pass':True,'phase':phase,'build':str(b),'retained_total_frames':32,'snapshot_width':32,'debug_CRC_and_window_cones_removed':True,'registers':rows,'functional_difference':'reports/TEST_PIPELINE.json replay_count, 70760 exact SYS-cycle comparisons including clear/reset/busy and UI','production_progress_consumer':'replay_progress retained unchanged'}
(r/f'reports/WITNESS_{"SYNTH" if phase=="synthesized" else "ROUTED"}.json').write_text(json.dumps(v,indent=2)+'\n')
print('RELEASE_PROGRESS_COUNTER_NATIVE_PASS',phase,flush=True)
