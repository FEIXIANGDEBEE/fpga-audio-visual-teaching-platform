"""V15.1 new power controls in the unique protected synthesis object."""
from pathlib import Path
import json, itertools
from scene_mapped_graph import graph, bits
R=Path(__file__).resolve().parents[1]
B=Path(json.loads((R/'reports/SYNTHESIS_B.json').read_text())['path'])
g=graph((B/'protected.v').read_text())
aliases={w['o']:w['i'] for k,p,w in g.values() if k=='buf'}
def root(n):
    seen=set()
    while n in aliases:
        assert n not in seen;seen.add(n);n=aliases[n]
    return n
assert root(r'\microphone/rst_n')==root(r'\eco_sys_reset/release_pipe[2]')
rows=[]
for bank in (0,1):
    cells=[(n,p,w) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM') and f'analysis/input_windows/ramread{bank}_' in n]
    assert len(cells)==1,cells
    n,p,w=cells[0]
    assert p['CSB2']=='"SIG"' and p['CEBMUX']=='"1"'
    control=bits(w['csb'])[0]
    drivers=[(cn,cp,cw) for cn,(ck,cp,cw) in g.items() if ck=='AL_MAP_LUT3' and cw.get('o')==control]
    assert len(drivers)==1,drivers
    cn,cp,cw=drivers[0]
    assert cw['a']==r'\analysis/input_windows/process_bank'
    assert root(cw['b'])==root(r'\analysis/reset/release_pipe[2]'),cw
    assert cw['c']==r'\analysis/input_windows/phase_reg_syn_1[1]'
    init=cp['INIT'][1]
    for a,b,c in itertools.product((0,1),repeat=3):
        actual=(init>>(a+2*b+4*c))&1
        assert actual==int(b and c and a==bank),(bank,a,b,c,actual)
    rows.append(dict(bank=bank,cell=n,read_control=control,driver=cn,truth_table_exhaustive=True,reset_disables_read=True,selected_bank_only=True))
assert not any('analysis/input_windows/sample_reg' in n for n in g)
result=dict(pass_=True,build=str(B),stage='protected',window_RAM=rows,microphone_reset='eco_sys_reset/release_pipe[2]',duplicate_sample_register_removed=True,hardware_accessed=False)
result['pass']=result.pop('pass_')
(R/'reports/V151_PROTECTED_POWER.json').write_text(json.dumps(result,indent=2)+chr(10))
print('V151_PROTECTED_POWER_PASS',flush=True)
