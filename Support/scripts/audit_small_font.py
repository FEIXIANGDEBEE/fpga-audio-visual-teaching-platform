"""Decode all new native 32K small-font cells; no unchecked UI-bank exclusions."""
from pathlib import Path
import sys,json,re
from scene_mapped_graph import graph,bits
from scene_common import ROOT,write_json
role=sys.argv[1];build=Path(json.loads((ROOT/f'reports/BUILD_{role.upper()}_ACTIVE.json').read_text())['path'])
SRC=ROOT/f'source/{role}'
g=graph((build/'synthesized.v').read_text());prefix='media/osd/text_engine/small_font/' if role=='a' else 'screen/render/text_engine/small_font/'
found={};rows=[]
for name,(kind,p,w) in g.items():
 if prefix not in name or not kind.startswith('EG_PHY_BRAM'):continue
 bank=int(re.search(r'bank([0-2])',name)[1]);narrow=bank==2
 assert kind==('EG_PHY_BRAM' if narrow else 'EG_PHY_BRAM32K'),name
 assert p['WEAMUX']=='"0"' and p['WEBMUX']=='"0"' and p['REGMODE_A']=='"NOREG"',name
 assert p['DATA_WIDTH_A'] in (['"9"'] if narrow else ['"16"','"18"']),(name,p['DATA_WIDTH_A'])
 if narrow:
  indices=[int(m[1]) for bit in bits(w['doa']) if (m:=re.search(r'/rows\[(\d+)\]',bit))]
  lane=min(indices)-32;assert lane in [0,9]
  key=(bank,lane);assert key not in found
  raw=sum(p[f'INIT_{i:02X}'][1]<<(256*i) for i in range(32))
  parity=sum(p[f'INITP_{i:02X}'][1]<<(256*i) for i in range(4))
  words=[((raw>>(i*8))&255)|(((parity>>i)&1)<<8) for i in range(1024)]
  logical=[int(v,16) for v in (SRC/f'font_{role}_small2.dath').read_text().split()]
  want=[(x>>lane)&511 for x in logical]+[0]*512
  address=bits(w['addra'])
  assert address==["1'b0"]+[prefix.join(['\\','address'])+f'[{i}]' for i in range(8,-1,-1)]+["1'b1"]*3,(name,'native9K row address',address)
 else:
  key=bank;assert key not in found
  raw=sum(p[f'INIT_{i:02X}'][1]<<(256*i) for i in range(128))
  words=[(raw>>(i*16))&65535 for i in range(2048)]
  want=[int(v,16) for v in (SRC/f'font_{role}_small{bank}.dath').read_text().split()]
  for k,value in p.items():
   if k.startswith('INITP_'):assert value[1]==0,(name,'unused parity not zero')
 assert words==want,(name,'INIT differs')
 enable=w.get('csa',w.get('cea'))
 assert enable and "'" not in enable and p.get('CSAMUX','"SIG"')=='"SIG"',(name,'font enable missing',enable)
 found[key]=name;rows.append({'cell':name,'bank':bank,'kind':kind,'configured_width':p['DATA_WIDTH_A'],'values':1024 if narrow else 2048,'INIT_exact':True,'write_disabled':True,'clock':w.get('clka'),'enable':enable})
assert set(found)=={0,1,(2,0),(2,9)},found
assert len(set(x['clock'] for x in rows))==1,'Font banks changed clock domains'
result={'pass':True,'board':role,'build':str(build),'native_bram32k':2,'native_bram9k':2,'words_compared':4608,'write_disabled':True,'clock_enable':'Same pixel clock, synchronous enable; exhaustive RTL tests cover hold/read transitions','latency':'One native read with bank-select register; same three-stage video interface','cells':rows}
write_json(ROOT/f'reports/SMALL_FONT_{role.upper()}_INIT.json',result)
print('SMALL_FONT_NATIVE_INIT_PASS',role,result['words_compared'],flush=True)
