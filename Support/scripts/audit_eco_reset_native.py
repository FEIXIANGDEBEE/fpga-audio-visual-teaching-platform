"""Read-only proof of the four affected native reset-release chains and timed stages."""
from pathlib import Path
import json,re
from scene_mapped_graph import graph,bits
from audit_v3 import run
R=Path(__file__).resolve().parents[1]
B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
g=graph((B/'routed.v').read_text());chains={};pairs=[]
alias={a:b for k,p,w in g.values() if k=='buf' for a,b in zip(bits(w['o']),bits(w['i']))}
def root(n):
    seen=set()
    while n in alias:
        assert n not in seen;seen.add(n);n=alias[n]
    return n
domains=['eco_sys_reset','eco_audio_reset','screen/source_reset','screen/reset','microphone/heartbeat_reset','microphone/mic_reset','microphone/mail_reset']
for domain in domains:
    rows=[]
    for i in range(3):
        q='\\'+domain+f'/release_pipe[{i}]';found=[]
        for n,(k,p,w) in g.items():
            if k not in ['EG_PHY_MSLICE','EG_PHY_LSLICE']:continue
            for lane,v in enumerate(reversed(bits(w.get('q','')))):
                if root(v)==root(q):found.append((n,lane,p,w))
        assert len(found)==1,(q,found)
        n,lane,p,w=found[0]
        assert p['SRMODE']=='"ASYNC"' and p['SRMUX']=='"INV"' and p['CEMUX']=='"1"'
        assert p[f'REG{lane}_REGSET']=='"RESET"' and p[f'REG{lane}_SD']=='"MI"'
        d=list(reversed(bits(w['mi'])))[lane]
        assert root(d)==root("1'b1" if i==0 else '\\'+domain+f'/release_pipe[{i-1}]'),(q,d)
        rows.append(dict(q=q,cell=n,lane=lane,clk=w['clk'],sr=w['sr'],d=d))
    assert len({x['clk'] for x in rows})==len({x['sr'] for x in rows})==1
    chains[domain]=rows
    for a,b in zip(rows,rows[1:]):pairs.append((a['cell'].lstrip('\\')+f'.q[{a["lane"]}]',b['cell'].lstrip('\\')+f'.mi[{b["lane"]}]'))
assert chains['eco_sys_reset'][0]['clk']==chains['screen/source_reset'][0]['clk']
assert len({chains[d][0]['clk'] for d in ['eco_sys_reset','eco_audio_reset','screen/reset']})==3
assert chains['screen/source_reset'][0]['sr']==chains['screen/reset'][0]['sr']
lines=['import_device eagle_s20.db -package EG4S20BG256','import_db routed.db','set_param flow thread 8','update_timing -mode final']
for i,(a,b) in enumerate(pairs):
    lines += [f'set a [get_pins -hier {{{a}}}]',f'set b [get_pins -hier {{{b}}}]',
        'if {[llength $a]!=1 || [llength $b]!=1} {error {reset stage pin absent or ambiguous}}',
        f'report_timing_path -from $a -to $b -ep_num 10 -file eco_reset_stage_{i}.timing']
run(B,'eco_reset_query',lines)
stages=[]
for i,(a,b) in enumerate(pairs):
    t=(B/f'eco_reset_stage_{i}.timing').read_text()
    slack=[float(v) for v in re.findall(r'^Slack\s+:\s*([-+\d.]+)ns',t,re.M)]
    assert slack and min(slack)>=0,(i,slack)
    assert 'Check Type          : setup' in t and 'Check Type          : hold' in t,(i,t)
    stages.append(dict(source=a,destination=b,min_slack_ns=min(slack)))
result=dict(pass_=True,build=str(B),native_chains=chains,timed_stages=stages,
    scope='Exact packed three-flop async assertion/synchronous release, distinct domains and all 14 stage setup/hold paths including microphone; behavioral policy tested separately',hardware_accessed=False)
result['pass']=result.pop('pass_')
(R/'reports/V15_ECO_RESET_NATIVE.json').write_text(json.dumps(result,indent=2)+'\n')
print('V151_ECO_RESET_NATIVE_PASS',len(chains),'chains',len(stages),'timed stages')
