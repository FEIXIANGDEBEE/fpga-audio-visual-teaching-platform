"""Audit actual EG4S20 DP8K port widths, bit lanes and every palette entry.

The plan's one-block palette estimate is corrected in EXECUTION_DEVIATIONS.md:
DP8K supports nine bits per port, so exact24bit palette requires three blocks.
"""
from pathlib import Path
import sys,json,re,collections
from scene_common import ROOT,write_json
from scene_mapped_graph import graph,bits
phase=sys.argv[1];assert phase in ('synthesized','routed')
B=Path(json.loads((ROOT/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
g=graph((B/(phase+'.v')).read_text());prefix='\\screen/render/spectrogram/'
ram={n:(k,p,w) for n,(k,p,w) in g.items() if n.startswith(prefix) and k.startswith('EG_PHY_BRAM')}
hist={n:(p,w) for n,(k,p,w) in ram.items() if '/hist_' in n};pal={n:(p,w) for n,(k,p,w) in ram.items() if '/pal_' in n}
assert len(hist)==8 and len(pal)==3 and len(ram)==11,(len(hist),len(pal))
assert all(k=='EG_PHY_BRAM' for k,p,w in ram.values())
palette=[int(s,16) for s in (ROOT/'source/b/spectrum_palette.dath').read_text().split()];assert len(palette)==256
decoded=[0]*256;seen=set();histlanes=set();rows=[]
for n,(p,w) in hist.items():
 assert p['MODE']=='"DP8K"' and p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"1"'
 assert p['REGMODE_A']==p['REGMODE_B']=='"NOREG"' and p['WEBMUX']=='"0"'
 assert p['RSTAMUX']==p['RSTBMUX']=='"0"'
 assert len(bits(w['addra']))==len(bits(w['addrb']))==13
 # Synthesis exchanges logical A(read)/B(write) into physical B/A. Check real
 # ports rather than assuming that logical and physical port letters match.
 outs=[(i,net) for i,net in enumerate(reversed(bits(w['dob']))) if '/hist_q[' in net]
 ins=[(i,net) for i,net in enumerate(reversed(bits(w['dia']))) if '/wd[' in net]
 # EG4 DP8K x1 uses DIA[1] for write data and DOB[0] for read data.
 assert len(outs)==len(ins)==1 and outs[0][0]==0 and ins[0][0]==1,(n,ins,outs)
 lane=int(re.search(r'\[(\d+)\]',outs[0][1])[1]);assert lane not in histlanes
 assert ins[0][1].endswith('/wd['+str(lane)+']');histlanes.add(lane)
 if phase=='synthesized':
  assert list(reversed(bits(w['addra'])))==[prefix+f'wr_idx[{i}]' for i in range(4)]+[prefix+f'wr_ptr[{i}]' for i in range(9)]
  assert w['wea']==w['cea']==prefix+'we'
 rows.append({'cell':n,'shape':'8192x1','energy_bit':lane,'read':'B','write':'A','no_reset':True})
assert histlanes==set(range(8))
for n,(p,w) in pal.items():
 assert p['MODE']=='"DP8K"' and p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"9"'
 assert p['WEAMUX']==p['WEBMUX']=='"0"' and p['REGMODE_A']=='"NOREG"'
 assert p['CEAMUX']=='"1"' and p['OCEAMUX']=='"1"'
 raw=sum(p[f'INIT_{i:02X}'][1]<<(256*i) for i in range(32))
 parity=sum(p[f'INITP_{i:02X}'][1]<<(256*i) for i in range(4))
 local=[((raw>>(8*i))&255)|(((parity>>i)&1)<<8) for i in range(256)]
 lanes=[]
 for lane,net in enumerate(reversed(bits(w['doa']))):
  if '/pal_q[' in net:idx=int(re.search(r'\[(\d+)\]',net)[1])
  elif '/half_color[' in net:
   alias=int(re.search(r'\[(\d+)\]',net)[1]);assert alias%8<7
   idx=alias+1 # Channel floor(c/2): source i+1 aliases half bit i.
  else:continue
  assert idx not in seen;seen.add(idx);lanes.append(idx)
  for i in range(256):decoded[i]|=((local[i]>>lane)&1)<<idx
 assert lanes
 addr=list(reversed(bits(w['addra'])))
 assert addr[3:11]==[prefix+f'hist_q[{i}]' for i in range(8)],(n,addr)
 rows.append({'cell':n,'shape':'1024x9 used256','RGB_bits':lanes,'INIT_entries_exact':256})
assert seen==set(range(24)) and decoded==palette,'Palette INIT/bit-lane mismatch'
clocks={w['clka'] for k,p,w in ram.values()}|{w['clkb'] for k,p,w in ram.values()}
assert len(clocks)==1,clocks
assert not [n for n,(k,p,w) in g.items() if n.startswith(prefix) and k.startswith('EG_PHY_MULT')]
if phase=='synthesized':
 regs=[(p,w) for n,(k,p,w) in g.items() if n.startswith(prefix) and k=='AL_MAP_SEQ']
 assert len(regs)==23,len(regs) # filled saturates288: bit8 is live.
 assert {w['clk'] for p,w in regs}==clocks=={'\\screen/wave_read_clk'}
 assert all(p['SRMODE']=='"ASYNC"' and w['sr']=='\\screen/prst' for p,w in regs)
 count9=sum(k=='EG_PHY_BRAM' for k,p,w in g.values());assert count9==41 and count9<=50,count9
 # This tool does not emit a final packed MSLICE count during synthesis. Its
 # LUT estimate is not promoted to a physical count. Enforce4750 on the first
 # actual placed native object, before any detailed routing.
 inventory=dict(collections.Counter(k for k,p,w in g.values()))
else:
 protected=graph((B/'protected.v').read_text())
 assert {n:(k,p) for n,(k,p,w) in ram.items()}=={n:(k,p) for n,(k,p,w) in protected.items() if n in ram}
 inventory={}
report={'pass':True,'build':str(B),'phase':phase,'history9K':8,'palette9K':3,'palette24bit_all256_exact':True,
 'new9K':11,'plan_estimate_corrected':'EXECUTION_DEVIATIONS.md','clock':list(clocks),'history_RAM_reset':False,
 'new_DSP':0,'cells':rows,'inventory':inventory,'MSLICE_pre_route_gate':4750,'physical_hard_gate':4900}
write_json(ROOT/f'reports/V127_NATIVE_{phase.upper()}.json',report)
print('V127_NATIVE_PASS',phase,'8 history9K +3 palette9K; all256x24 INIT and lanes exact; same pixel clock',flush=True)
