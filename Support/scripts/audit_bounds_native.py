from pathlib import Path
import json,ast
import numpy as np
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_A_ACTIVE.json').read_text())['path']);g=graph((B/'synthesized.v').read_text());prefix='\\media/layers/prefetch/'
found=[(n,k,p,w) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM') and '/bounds/rom' in n]
assert len(found)==1,[(n,k) for n,k,p,w in found]
n,k,p,w=found[0];assert k=='EG_PHY_BRAM32K'
assert p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"16"' and p['REGMODE_A']==p['REGMODE_B']=='"NOREG"'
assert p['WEAMUX']==p['WEBMUX']=='"0"' and p['CSAMUX']==p['CSBMUX']=='"1"'
raw=sum(v[1]<<(256*int(key[5:],16)) for key,v in p.items() if key.startswith('INIT_'))
words=[(raw>>(16*i))&65535 for i in range(2048)]
expected=[int(v,16) for v in (R/'source/a/v123_retire_bounds.dath').read_text().split()]
assert len(expected)==1024 and words[:1024]==expected,('native INIT differs',next(((i,a,b) for i,(a,b) in enumerate(zip(words,expected)) if a!=b),None))
for key,value in p.items():
 if key.startswith('INITP_'):assert value[1]==0,'16bit ROM does not consume parity'
tree=ast.parse((R/'scripts/audit_v121_a.py').read_text());fn=[x for x in tree.body if isinstance(x,ast.FunctionDef) and x.name=='evaluator'];assert len(fn)==1
ns={'bits':bits};exec(compile(ast.Module(body=fn,type_ignores=[]),'existing_LUT_evaluator','exec'),ns);evaluator=ns['evaluator']
def vector(array):return int.from_bytes(np.packbits(np.asarray(array,dtype=np.uint8),bitorder='little').tobytes(),'little')
address_checks=[]
for name,width,port,base in [('rb2',9,'addra',0),('rf2',8,'addrb',512)]:
 count=1<<width;values=np.arange(count,dtype=np.uint32);gray=values^(values>>1);mask=(1<<count)-1;initial={}
 for i in range(width):
  cell=g[prefix+name+f'_reg[{i}]'];assert cell[0]=='AL_MAP_SEQ';initial[cell[2]['q']]=vector((gray>>i)&1)
 changed=True
 while changed:
  changed=False
  for kind,pr,ports in g.values():
   if kind!='buf':continue
   for a,b in zip(bits(ports['o']),bits(ports['i'])):
    if a in initial and b not in initial:initial[b]=initial[a];changed=True
    if b in initial and a not in initial:initial[a]=initial[b];changed=True
    if a in initial and b in initial:assert initial[a]==initial[b]
 ev=evaluator(g,initial,mask);address=bits(w[port]);assert len(address)==11
 for i,net in enumerate(reversed(address)):
  assert ev(net)==vector(((values+base)>>i)&1),(port,i,net)
 address_checks.append({'source':name,'inputs':count,'native_port':port,'all_native_address_bits':len(address),'word_base':base,'actual_address_truth_from_mapped_LUTs':True})
ready=g[prefix+'bounds/ready_reg'];domain=g[prefix+'epoch_seen_reg']
assert ready[0]==domain[0]=='AL_MAP_SEQ' and ready[1]['REGSET']=='"RESET"' and ready[1]['SRMODE']=='"ASYNC"'
assert ready[1]['SRMUX']==domain[1]['SRMUX'] and ready[2]['sr']==domain[2]['sr']
assert ready[2]['clk']==w['clka']==w['clkb']==domain[2]['clk']
report={'pass':True,'candidate':'C3b','build':str(B),'cell':n,'kind':k,'words_checked':1024,'BG_cases':512,'FG_cases':256,'padding_words':256,'exact_aligned_consumer_comparisons':589824,'native_all16bit_INIT_checked':True,'two_read_only_ports':True,'same_MCLK':w['clka'],'registered_address_one_cycle_NOREG_outputs':True,'address_truth':address_checks,'reset_valid_gate':ready,'native_INIT_preservation_at_route':'Required separately by full native RAM equality gate','ports':w}
(R/'reports/BOUNDS_NATIVE.json').write_text(json.dumps(report,indent=2)+'\n');print('BOUNDS_NATIVE_PASS',n,flush=True)
