"""Verify INIT/clock and real Q/data/enable aliases for the same-edge release."""
from pathlib import Path
import re,ast
from scene_mapped_graph import bits
def prove(pg,sg):
    src=sg['\\startup/released_reg'];assert src[0]=='AL_MAP_SEQ' and src[1]['__REG_INIT__']==0 and src[1]['SRMUX']=='"0"' and 'sr' not in src[2]
    parent={}
    def root(x):
        parent.setdefault(x,x)
        if parent[x]!=x:parent[x]=root(parent[x])
        return parent[x]
    for g in [sg,pg]:
        for k,p,w in g.values():
            if k=='buf':
                for a,b in zip(bits(w['o']),bits(w['i'])):parent[root(a)]=root(b)
    qdrivers={}
    for n,(k,p,w) in pg.items():
        if k in ['EG_PHY_MSLICE','EG_PHY_LSLICE']:
            for lane,q in enumerate(reversed(bits(w.get('q','')))):
                if not q.startswith('open_n'):qdrivers[root(q)]=(n,k,p,w,lane,q)
    # Packing can remove the logical original while retaining several real
    # equivalent Q copies. Require live physical drivers, not the old alias.
    want={x for x in [root(src[2]['q']),root('rst_n')] if x in qdrivers}
    for q in qdrivers:
        if re.fullmatch(r'rst_n_dup_\d+',q) or re.fullmatch(r'\\startup/released(?:_syn_\d+)?(?:_dup_\d+)?',q):want.add(q)
    for n,(k,p,w) in pg.items():
        if k in ['EG_PHY_MSLICE','EG_PHY_LSLICE'] and any(re.fullmatch(r'current_valid(?:_dup_\d+)?',q) for q in bits(w.get('q',''))):want.add(root(w['sr']))
    drivers=[];roots=[]
    for q in sorted(want):
        assert q in qdrivers,('Reset source must have a real FF Q driver',q)
        n,k,p,w,lane,raw=qdrivers[q]
        assert root(w['clk'])==root(src[2]['clk']) and p['CLKMUX']=='"CLK"'
        assert p.get(f'REG{lane}_REGSET','"RESET"')=='"RESET"'
        sd=p[f'REG{lane}_SD'];pin={'"MI"':'mi','"FX"':'fx','"F"':'f'}[sd];d=list(reversed(bits(w[pin])))[lane]
        ce=w.get('ce',"1'b1");pc=p.get('CEMUX','"1"');sc=src[1].get('CEMUX','"1"')
        same_data=root(d)==root(src[2]['d']);same_ce=pc==sc and (pc=='"1"' or root(ce)==root(src[2].get('ce',"1'b1")))
        assert same_data and same_ce,('Packed release D/CE must retain the proven logical next-value net',n,sd,d,src[2],pc,sc)
        drivers.append({'cell':n,'lane':lane,'Q':raw,'clock':w['clk'],'D_selected_pin':pin,'D':d,'enable_mux':pc,'native_reset_value':0,'logical_D_and_CE_identical_to_synthesis':True});roots.append(q)
    assert drivers
    return {'pass':True,'source_synthesis_cell':'startup/released_reg','synthesis_INIT':0,'source_CLK':src[2]['clk'],'same_logical_release_edge':1023,'new_pipeline_latency':0,'counter_inits_and_next_function':'POWER_RESET_SYNTH.json','native_drivers':drivers,'proven_reset_roots':roots,'method':'Each real FF Q driver has the INIT/reset value0 and same CLK/D/CE as the cycle-proven release register; buffer aliases traced from actual connectivity'}
