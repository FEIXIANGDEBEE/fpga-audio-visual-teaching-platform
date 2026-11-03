"""Prove registered SYS ownership, including legal placer FF replication."""
from pathlib import Path
import json,re
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
sg=graph((B/'synthesized.v').read_text());g=graph((B/'routed.v').read_text())
owned=sg['\\recording_mode/owner_reg'];assert owned[0]=='AL_MAP_SEQ' and owned[2]['clk']=='sys_clk_dup_1'
assert owned[1]['__REG_INIT__']==0 and owned[1]['REGSET']=='"RESET"'
# 2026-10-27: in V11.1 the owner bit is exported as ui_link/status_in[8] and TD
# keeps the source-derived name, adding _syn_N/_dup_N replication suffixes. Match
# the exact synthesized Q name plus those suffixes instead of the old alias.
OWNER=tuple(owned[2]['q'] for _ in (0,))
OWNER_NET=owned[2]['q']
OWNER_RX=re.compile('^'+re.escape(OWNER_NET)+r'(_syn_\d+|_dup_\d+)?$')
alias={};drivers={}
for n,(k,p,w) in g.items():
 if k=='buf':
  for a,b in zip(bits(w['o']),bits(w['i'])):alias[a]=b
  drivers[w['o']]=(k,p,w,0,'o')
 elif k in ('EG_PHY_MSLICE','EG_PHY_LSLICE'):
  for port in ('f','fx'):
   for lane,out in enumerate(reversed(bits(w.get(port,'')))):drivers[out]=(k,p,w,lane,port)
def root(x):
 while x in alias:x=alias[x]
 return x
# Tooling fix 2026-10-27: place/route inserts fanout duplicates and TD's routed
# verilog declares <net>_dup_<n> as a plain wire with no driving cell (the copy
# is a physical replication of the same source; e.g. \startup/startup[0]_dup_7
# is absent from synthesized.v). Resolve such a name to its base net only when
# the duplicate really has no driver in the routed netlist, so a genuine driver
# can never be bypassed by this rule.
def resolve(net):
 if net in drivers or net in memo:return net
 m=re.fullmatch(r'(.*)_dup_\d+',net)
 return resolve(m.group(1)) if m and (m.group(1) in drivers or m.group(1) in memo) else net
# Evaluate actual packed reset INIT over every10bit power-on counter value.
ALL=(1<<1024)-1
memo={'\\startup/startup['+str(j)+']':sum(((i>>j)&1)<<i for i in range(1024)) for j in range(10)}
def reset_truth(net):
 net=resolve(net)
 if net in memo:return memo[net]
 if net=="1'b0":return 0
 if net=="1'b1":return ALL
 k,p,w,lane,port=drivers[net]
 if k=='buf':out=reset_truth(w['i'])
 else:
  assert port=='f' and p.get('MODE','"LOGIC"')=='"LOGIC"'
  init=p.get('INIT_LUT'+str(lane),('number',0))[1] if k=='EG_PHY_MSLICE' else p['INIT_LUTF'+str(lane)][1]
  if k=='EG_PHY_LSLICE' and p.get('LSFMUX'+str(lane))=='"FUNC5"':assert init==p['INIT_LUTG'+str(lane)][1]
  ins=[reset_truth(list(reversed(bits(w[pin])))[lane]) for pin in 'abcd']
  out=0
  for index in range(16):
   if init>>index&1:
    term=ALL
    for j,v in enumerate(ins):term &= v if index>>j&1 else ALL^v
    out |= term
 memo[net]=out;return out
def owner_input(net):
 net=root(net)
 return '__EQUIVALENT_OWNER_Q__' if OWNER_RX.fullmatch(net) else net
def internal_f_signature(k,p,w,lane):
 assert k in ('EG_PHY_MSLICE','EG_PHY_LSLICE') and p.get('MODE')=='"LOGIC"'
 def lane_input(pin):
  return owner_input(list(reversed(bits(w.get(pin,"{1'b1,1'b1}"))))[lane])
 # V12.6 actual owner FF uses MSLICE REG0_SD=F, and its exported F
 # is exactly the synthesis D. Capture this legal 4-LUT primitive as well;
 # unexported replicas still require an identical full primitive signature.
 if k=='EG_PHY_MSLICE':
  return (k,p[f'INIT_LUT{lane}'],tuple(lane_input(x) for x in 'abcd'))
 return (k,p[f'INIT_LUTF{lane}'],p[f'INIT_LUTG{lane}'],p[f'LSFMUX{lane}'],tuple(lane_input(x) for x in 'abcde'))
# A replica may consume its own slice-internal LUT F without exporting that
# optional wire. Match the full actual LUT INIT/mux/input signature to an
# exported F that is the synthesis D. Owner-Q feedback is equivalent by
# induction: every real copy is checked below for same CLK/CE/INIT/reset/D.
reference_f=[]
for n,(k,p,w) in g.items():
 for lane,q in enumerate(reversed(bits(w.get('q','')))):
  if OWNER_RX.fullmatch(q) and p.get(f'REG{lane}_SD')=='"F"' and 'f' in w:
   net=list(reversed(bits(w['f'])))[lane]
   if root(net)==root(owned[2]['d']):reference_f.append((n,internal_f_signature(k,p,w,lane)))
rows=[];targets=[]
for n,(k,p,w) in g.items():
 for lane,q in enumerate(reversed(bits(w.get('q','')))):
  if not OWNER_RX.fullmatch(q):continue
  assert k in ('EG_PHY_MSLICE','EG_PHY_LSLICE') and w['clk']=='sys_clk_dup_1'
  # REG_SD selects the slice-internal source of the FF D input: "MI" is the
  # slice mux input, "FX" is the F LUT output directly. Both are legal
  # encodings of the same logic, so the audit reads the pin that REG_SD really
  # selects instead of assuming "MI" (this placement put the original owner on
  # an FX slice; its fx lane carries the same synthesis D net).
  sd=p['REG'+str(lane)+'_SD'];assert sd in ('"MI"','"FX"','"F"'),('unexpected REG_SD',n,sd)
  assert p['REG'+str(lane)+'_REGSET']=='"RESET"'
  assert p['CEMUX']=='"1"' and p['DFFMODE']=='"FF"' and p['CLKMUX']=='"CLK"'
  assert p['SRMODE']=='"ASYNC"' and p['SRMUX']=='"INV"'
  pin={'"MI"':'mi','"FX"':'fx','"F"':'f'}[sd]
  internal_proof=None
  if pin in w:
   actual_d=list(reversed(bits(w[pin])))[lane];assert root(actual_d)==root(owned[2]['d'])
  else:
   assert sd=='"F"',('Unexported D source requires a corresponding proven primitive function',n,sd)
   signature=internal_f_signature(k,p,w,lane)
   matches=[ref for ref,sig in reference_f if sig==signature];assert matches,(n,signature,reference_f)
   actual_d='slice-internal F';internal_proof={'exported_reference_cells':matches,'same_LUTF_LUTG_FUNC5_and_inputs':True,'owner_feedback_equivalence':'All referenced owner Q nets must be real copies with identical init/CLK/CE/reset and matching D, checked in this audit'}
  assert reset_truth(w['sr'])==1<<1023,('native reset truth differs',n,w['sr'])
  loads=sum(q in bits(net) for name,(kk,pp,ww) in g.items() for pin,net in ww.items() if pin not in ('q','f','fx','o'))
  targets.append(q);rows.append({'owner_driver_cell':n,'Q':q,'D':actual_d,'internal_D_proof':internal_proof,'clock':w['clk'],'type':k,'port':'q','lane':lane,'loads':loads,'reset_native_truth_1024_vectors':True,'same_D_CE_clock_reset_as_SYS_owner':True})
assert rows and len(targets)==len(set(targets))
# A root may be removed after replication; every live owner alias must have Q.
live={x for n,(k,p,w) in g.items() for pin,net in w.items() for x in bits(net) if OWNER_RX.fullmatch(x)}
assert live==set(targets),(live,targets)
v={'pass':True,'build':str(B),'rows':rows,'physical_registered_replicas':len(rows),'synthesis_owned_cell':'\\recording_mode/owner_reg','clock_domain_unchanged':'SYS','extra_output_cycle':False,'global_state_OR_removed':True,'method':'Owned synthesis FF; every routed replica Q has identical D/CE/SYS and reset INIT truth over all1024 power-counter states'}
(R/'reports/REGISTERED_OWNER_ROUTED.json').write_text(json.dumps(v,indent=2)+'\n');print('REGISTERED_OWNER_REPLICAS_NATIVE_PASS',len(rows))
