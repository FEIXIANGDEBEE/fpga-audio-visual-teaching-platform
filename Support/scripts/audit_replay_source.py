"""Prove registered completed-frame source and atomic historical identity."""
from pathlib import Path
import json,sys
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1]
B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
phase='synthesized' if '--synthesis' in sys.argv else 'routed'
g=graph((B/(phase+'.v')).read_text());aliases={}
for n,(k,p,w) in g.items():
 if k=='buf':
  for a,b in zip(bits(w['o']),bits(w['i'])):aliases[a]=b
def root(x):
 seen=set()
 while x in aliases:
  assert x not in seen;seen.add(x);x=aliases[x]
 return x
if phase=='synthesized':
 pll=g['\\screen/pll/pll_inst'];assert pll[0]=='EG_PHY_PLL'
 pixel_clock=list(reversed(bits(pll[2]['clkc'])))[1]
 anchors=[('banks/serial/current_tag_reg[3]','audio_mclk_dup_1','\\banks/serial/replay_select'),
  ('banks/serial/sent_tag_reg[3]','audio_mclk_dup_1','\\banks/serial/current_tag[3]'),
  ('analysis/pcm/held_reg[35]','audio_mclk_dup_1','\\banks/serial/sent_tag[3]'),
  ('analysis/pcm/ddata_reg[35]','sys_clk_dup_1','\\analysis/pcm/held[35]')]
 identity_sources={131:'\\analysis/record_page[0]',132:'\\analysis/record_page[1]',135:'\\analysis/record_right',136:'\\analysis/record_mic',139:'\\analysis/record_page[2]',140:'\\analysis/record_page[3]'}
 for bit in [131,132,135,136,139,140]:
  anchors += [(f'screen/audio_snapshot/held_data_reg[{bit}]','sys_clk_dup_1',identity_sources[bit]),
              (f'screen/audio_snapshot/snapshot_reg[{bit}]',pixel_clock,f'\\screen/audio_snapshot/held_data[{bit}]')]
 actual_pcm={int(n.split('[')[-1][:-1]) for n in g if n.startswith('\\analysis/pcm/held_reg[')}
 assert actual_pcm==set(range(52))-{40,41,42,43},actual_pcm
 actual_plot={int(n.split('[')[-1][:-1]) for n in g if n.startswith('\\screen/audio_snapshot/held_data_reg[')}
 # V12.5 uses height bit0 in the quarter-fall feedback. All154 coherent bits
 # now have consumers; no mailbox/protocol width was added or split.
 assert actual_plot==set(range(163)),actual_plot
 assert not [n for n in g if 'serial/calibration_index_reg' in n or 'current_replay_reg' in n or 'active_replay_reg' in n or 'record_replay_reg' in n]
 rows=[]
 for name,clock,expected in anchors:
  n='\\'+name;assert n in g,n;k,p,w=g[n]
  assert k=='AL_MAP_SEQ' and w['clk']==clock,(name,k,w)
  if expected:assert root(w['d'])==root(expected),(name,w['d'],expected)
  rows.append({'owned_register':n,'clock':clock,'Q':w['q'],'D':w['d'],'type':k})
else:
 old=json.loads((R/'reports/REPLAY_SOURCE_SYNTH.json').read_text());rows=[]
 for original in old['registers']:
  target=root(original['Q']);drivers=[]
  for n,(k,p,w) in g.items():
   if k=='buf':continue
   for port in ('q','f','fx','o'):
    if target in [root(x) for x in bits(w.get(port,''))]:drivers.append((n,k,port))
  assert len(drivers)==1,(target,drivers)
  n,k,port=drivers[0];assert k in ('EG_PHY_MSLICE','EG_PHY_LSLICE') and port=='q',(target,drivers)
  rows.append({'synthesis_Q':original['Q'],'actual_Q_alias':target,'physical_register_cell':n,'port':port,'type':k})
result={'pass':True,'phase':phase,'build':str(B),'registers':rows,'production_calibrate_zero':True,'observer_mailbox_logical_bits':52,'observer_live_bits':48,'pruned_unused_historical_volume_bits':[40,41,42,43],'plot_identity_bundle_bits':163,
 'scope':'Completed-frame bit3 stages, original52bit mailbox and154bit atomic plot provenance; source calibration0 verified in production top test and absent calibration registers in native graph. Actual wide-bus timing checked by physical signoff'}
dest='REPLAY_SOURCE_SYNTH.json' if phase=='synthesized' else 'REPLAY_SOURCE_ROUTED.json'
(R/'reports'/dest).write_text(json.dumps(result,indent=2)+'\n')
print('V107_TAG_REGISTERED_SOURCE_PASS',phase,len(rows),flush=True)
