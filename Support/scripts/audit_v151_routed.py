"""Packed LUT truth for the new sleep controls and selected-bank RAM reads."""
from pathlib import Path
import ast,json
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1]
B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
g=graph((B/'routed.v').read_text())
alias={}
for k,p,w in g.values():
    if k=='buf':
        for a,b in zip(bits(w['o']),bits(w['i'])):alias[a]=b
def root(n):
    seen=set()
    while n in alias:
        assert n not in seen;seen.add(n);n=alias[n]
    return n
tree=ast.parse((R/'scripts/audit_v121_a.py').read_text())
fn=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='evaluator']
assert len(fn)==1
ns={'bits':bits}
exec(compile(ast.Module(body=fn,type_ignores=[]),'<packed LUT evaluator>','exec'),ns)
def ev_for(values,mask):
    initial={}
    for k,p,w in g.values():
        for net in w.values():
            for n in bits(net):
                if root(n) in values:initial[n]=values[root(n)]
    initial.update(values)
    return ns['evaluator'](g,initial,mask)
reset=root(r'\analysis/reset/release_pipe[2]')
bank=root(r'\analysis/input_windows/process_bank')
phase=root(r'\analysis/input_windows/phase_reg_syn_1[1]')
values={key:sum(((j>>i)&1)<<j for j in range(8)) for i,key in enumerate([bank,reset,phase])}
sg=graph((B/'protected.v').read_text())
sk,sp,sw=sg[r'\analysis/input_windows/process_bank_reg']
assert sk=='AL_MAP_SEQ' and sp['REGSET']=='"RESET"' and sp['CEMUX']=='"1"'
replicas=[]
for n,(k,p,w) in g.items():
    if k not in ('EG_PHY_MSLICE','EG_PHY_LSLICE'):continue
    for lane,q in enumerate(reversed(bits(w.get('q','')))):
        if 'analysis/input_windows/process_bank' not in q:continue
        select=p[f'REG{lane}_SD'];assert select in ('"MI"','"F"')
        assert p[f'REG{lane}_REGSET']==sp['REGSET']
        assert all(p[a]==sp[a] for a in ('CEMUX','CLKMUX','DFFMODE','SRMODE','SRMUX'))
        assert w['clk']==sw['clk'] and w['sr']==sw['sr']
        port='mi' if select=='"MI"' else 'f'
        assert root(list(reversed(bits(w[port])))[lane])==root(sw['d'])
        values[root(q)]=values[bank]
        replicas.append(dict(cell=n,lane=lane,q=q,data_select=select,identical_D_clock_CE_reset=True))
assert replicas
# Prove a fused D LUT at its own combinational inputs, without expanding
# unrelated comparator cones behind those inputs. Each absent/free physical
# input is enumerated too; every assignment must equal the protected LUT.
source_luts=[(n,k,p,w) for n,(k,p,w) in sg.items() if k.startswith('AL_MAP_LUT') and w.get('o')==sw['d']]
assert len(source_luts)==1
sn,sk,spar,sports=source_luts[0]
sinputs='abcdef'[:int(sk[10:])];snets=[root(sports[x]) for x in sinputs]
d_proof=[]
for replica in replicas:
    if replica['data_select']!='"F"':continue
    k,p,w=g[replica['cell']];lane=replica['lane']
    assert k=='EG_PHY_MSLICE', 'Review LSLICE fused F mux explicitly before accepting it'
    physical={}
    for pin in 'abcd':
        net=list(reversed(bits(w[pin])))[lane] if pin in w else None
        physical[pin]=None if net is None or net.startswith('open_n') or net in ("1'b0","1'b1") else root(net)
    assert sorted(v for v in physical.values() if v is not None)==sorted(snets), (physical,snets)
    free=[x for x,v in physical.items() if v is None];checked=0
    for sample in range(1<<len(sinputs)):
        inputs={snets[i]:(sample>>i)&1 for i in range(len(sinputs))}
        expected=(spar['INIT'][1]>>sample)&1
        for extra in range(1<<len(free)):
            pins={pin:(inputs[net] if net is not None else (extra>>free.index(pin))&1) for pin,net in physical.items()}
            index=sum(pins[x]<<i for i,x in enumerate('abcd'))
            assert (p[f'INIT_LUT{lane}'][1]>>index)&1==expected, (replica['cell'],sample,extra)
            checked+=1
    d_proof.append(dict(cell=replica['cell'],synthesized_LUT=sn,protected_INIT=spar['INIT'],physical_INIT=p[f'INIT_LUT{lane}'],inputs=physical,free_inputs_any_value=free,checked_assignments=checked,truth_identical=True))
ev=ev_for(values,255)
rows=[]
for i in (0,1):
    cells=[(n,p,w) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM') and f'analysis/input_windows/ramread{i}_' in n]
    assert len(cells)==1
    n,p,w=cells[0]
    assert p['CSB2']=='"SIG"' and p['CEBMUX']=='"1"'
    control=bits(w['csb'])[0]
    expected=sum(int(bool(j&2) and bool(j&4) and (j&1)==i)<<j for j in range(8))
    assert ev(control)==expected,(n,ev(control),expected)
    rows.append(dict(bank=i,cell=n,control=control,all_8_control_states_exact=True,sleep_disabled=True,other_bank_disabled=True))
chains=json.loads((R/'reports/V15_ECO_RESET_NATIVE.json').read_text())['native_chains']
eco=root(r'\eco_sys_reset/release_pipe[2]')
assert all(root(row['sr'])==eco for row in chains['microphone/heartbeat_reset'])
shared=root(chains['microphone/mic_reset'][0]['sr'])
assert all(root(row['sr'])==shared for domain in ('microphone/mic_reset','microphone/mail_reset') for row in chains[domain])
assert ev_for({eco:12,root('mic_alive'):10},15)(shared)==8
assert not any('analysis/input_windows/sample_reg' in n for n in g)
result=dict(pass_=True,build=str(B),window_RAM=rows,read_control_sources=[bank,reset,phase],process_bank_replicas=replicas,process_bank_D_proof=d_proof,method='Packed LUT INIT and actual wiring exhaustive control truth; RTL cycle differential reused',microphone_reset='eco_sys_reset/release_pipe[2]',duplicate_sample_register_removed=True,hardware_accessed=False,power_measured=False)
result['pass']=result.pop('pass_')
(R/'reports/V151_ROUTED_POWER.json').write_text(json.dumps(result,indent=2)+chr(10))
print('V151_ROUTED_POWER_PASS',flush=True)
