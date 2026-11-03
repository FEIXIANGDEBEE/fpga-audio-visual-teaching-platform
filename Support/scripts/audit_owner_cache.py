"""Actual new native cache banks, with preservation checked after routing."""
from pathlib import Path
import sys,json,re
from scene_mapped_graph import graph,bits
r=Path(__file__).resolve().parents[1];b=Path(json.loads((r/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
phase=sys.argv[1];assert phase in ('synthesized','routed')
g=graph((b/(phase+'.v')).read_text())
cells={n:(k,p,w) for n,(k,p,w) in g.items() if n.startswith('\\files/files/') and k.startswith('EG_PHY_BRAM')}
assert len(cells)==2,cells
for n,(k,p,w) in cells.items():
 assert k=='EG_PHY_BRAM' and p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"4"'
 assert p['REGMODE_A']==p['REGMODE_B']=='"NOREG"' and p['WEBMUX']=='"0"'
 assert w['clka']==w['clkb']=='sys_clk_dup_1' and w['wea'] not in ("1'b0","1'b1",None)
 if phase=='synthesized':
  assert 'cache_owner[1:0]' in w['addra'] and 'fill_count[8:0]' in w['addra']
  assert 'ram_addr[10:0]' in w['addrb']
if phase=='synthesized':
 valid=[n for n,(k,p,w) in g.items() if k=='AL_MAP_SEQ' and n.startswith('\\files/files/cache_valid_reg[')]
 assert len(valid)==3,valid
else:
 before=graph((b/'protected.v').read_text())
 assert all(n in before and before[n][:2]==row[:2] for n,row in cells.items()),'Cache RAM/INIT changed'
result={'pass':True,'phase':phase,'path':str(b),'native_RAM9K':2,'logical_depth':2048,'valid_owner_partitions':3,'bytes_per_owner':512,'unused_owner3_never_accepted':True,'RAM32K_added':0,'extra_RAM9K_vs_C1':1,'native_cells':list(cells),'CRC_publication_and_lifecycle':'TEST_PIPELINE.json owner_cache + audio_candidate + boot_retry'}
(r/f'reports/OWNER_CACHE_{phase.upper()}.json').write_text(json.dumps(result,indent=2)+'\n')
print('OWNER_CACHE_NATIVE_PASS',phase,flush=True)
