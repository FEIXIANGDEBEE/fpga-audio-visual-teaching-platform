"""Check intended debug deletion and retained observation in the actual object."""
from pathlib import Path
import sys,json
from scene_mapped_graph import graph
r=Path(__file__).resolve().parents[1];role,phase=sys.argv[1:3]
b=Path(json.loads((r/f'reports/BUILD_{role.upper()}_ACTIVE.json').read_text())['path']);g=graph((b/(phase+'.v')).read_text())
removed=['media/witness/','media/fx_diagnostics/','media/video_diagnostic/','media/subtitle_snapshot/'] if role=='a' else ['witness_snapshot/']
for prefix in removed:assert not [n for n in g if n.lstrip('\\').startswith(prefix)],prefix
if role=='a':
 assert not [n for n in g if any(n.lstrip('\\').startswith(s) for s in ['cache_hits_reg','cold_requests_reg','prefetches_reg'])]
 if phase=='synthesized':
  for group in ['media/audio_snapshot/held_data','media/audio_snapshot/snapshot']:
   names=[n for n,(k,p,w) in g.items() if k=='AL_MAP_SEQ' and n.startswith('\\'+group+'_reg[')]
   assert len(names)==64,(group,len(names))
else:
 assert not [n for n in g if n.lstrip('\\').startswith('diagnostic_keys_reg')]
 # Its name is historical: this mailbox also publishes the MIC warm-up bit.
 # That functional lane and its original CDC timing constraints must survive.
 if phase=='synthesized':
  warm=[n for n,(k,p,w) in g.items() if k=='AL_MAP_SEQ' and n.startswith('\\microphone/diagnostics/held_data_reg[')]
  assert warm==['\\microphone/diagnostics/held_data_reg[33]'],warm
if phase=='routed':
 before=graph((b/'protected.v').read_text())
 assert {n:(k,p) for n,(k,p,w) in before.items() if k.startswith('EG_PHY_BRAM')}=={n:(k,p) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM')},'Native RAM/INIT changed'
v={'pass':True,'board':role,'phase':phase,'build':str(b),'removed_debug_producers':removed,'A_PCM_snapshot_width':64 if role=='a' else None,'scope':'Actual native retained/deleted cells and RAM/INIT comparison; does not independently prove full behavior','behavioral_evidence':'TARGETED_TESTS.json for changed V15 cones; unchanged V14 legacy evidence reused'}
(r/f'reports/RELEASE_{role.upper()}_{phase.upper()}.json').write_text(json.dumps(v,indent=2)+'\n')
print('RELEASE_CONES_NATIVE_PASS',role,phase,flush=True)
