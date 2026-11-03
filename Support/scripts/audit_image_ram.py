"""Check the two-bank image buffer in this candidate's mapped/physical netlist."""
from pathlib import Path
import json, sys
from scene_mapped_graph import graph

root=Path(__file__).resolve().parents[1]
out=Path(json.loads((root/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
phase=sys.argv[1]
assert phase in ('synthesized','routed')
g=graph((out/(phase+'.v')).read_text())
found=[(n,k,p,w) for n,(k,p,w) in g.items() if 'image/' in n and k.startswith('EG_PHY_BRAM')]
assert len(found)==1, [(n,k) for n,k,_,_ in found]
n,k,p,w=found[0]
assert k=='EG_PHY_BRAM' and p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"9"'
assert p['REGMODE_A']==p['REGMODE_B']=='"NOREG"' and p['WEBMUX']=='"0"'
assert 'fetch_bank' in w['addra'],w['addra']
if phase=='synthesized':
 assert 'active_bank' in w['addrb'],w['addrb']
else:
 # Physical protection inserts a checked branch buffer on the read bank.
 guard=json.loads((out/'native_guard.json').read_text())
 assert guard['pass']
 bank_branches=[i for i,b in enumerate(guard['branches']) if b['source']=='\\image/active_bank'
                and any(s['cell']==n and s['port']=='addrb' for s in b['sinks'])]
 assert len(bank_branches)==1 and f'v3_ram_guard_{bank_branches[0]}' in w['addrb'],(bank_branches,w['addrb'])
assert w.get('wea') not in (None,"1'b0","1'b1")
if phase=='routed':
 before=graph((out/'protected.v').read_text())
 assert n in before and before[n][0]==k and before[n][1]==p,'native image RAM parameters changed'
report={'pass':True,'phase':phase,'cell':n,'type':k,'logical_depth':1024,'logical_width':8,
        'read_address':w['addrb'],'write_address':w['addra'],'write_enable':w['wea'],
        'protected_parameters_preserved':phase=='routed','build':str(out)}
(root/f'reports/IMAGE_RAM_{phase.upper()}.json').write_text(json.dumps(report,indent=2)+'\n')
print('IMAGE_RAM_PASS',phase,n)
