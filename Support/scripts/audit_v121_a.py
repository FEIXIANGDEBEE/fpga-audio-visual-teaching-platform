"""Audit the actual A object: native line memories and packed Gray decoders."""
from pathlib import Path
from collections import Counter
import json,sys,re
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1]
B=Path(sys.argv[1])
g=graph((B/'routed.v').read_text());sg=graph((B/'synthesized.v').read_text())
pg=graph((B/'protected.v').read_text())
native=lambda gg:{n:(k,p) for n,(k,p,w) in gg.items() if k.startswith('EG_PHY_BRAM')}
assert native(g)==native(pg),'Native RAM/INIT must be preserved'
line={n:(k,p,w) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM') and '/layers/prefetch/' in n and ('/bg_ram/' in n or '/fg_ram/' in n)}
assert Counter(k for k,p,w in line.values())=={'EG_PHY_BRAM':6,'EG_PHY_BRAM32K':2}
for n,(k,p,w) in line.items():
    bg='/bg_ram/' in n;assert bg or '/fg_ram/' in n
    assert p['DATA_WIDTH_A']==p['DATA_WIDTH_B']==('"4"' if bg else '"16"')
    assert p['REGMODE_A']==p['REGMODE_B']=='"NOREG"' and p['WEBMUX']=='"0"'
    assert w['clka']!=w['clkb'] and w.get('wea') not in [None,"1'b0","1'b1"]
    assert len(bits(w['addra']))==(13 if bg else 11)

def evaluator(gg,initial,allmask):
    memo=dict(initial);drivers={}
    for name,(k,p,w) in gg.items():
        if k=='buf':
            for o,i in zip(bits(w['o']),bits(w['i'])):drivers[o]=('buf',i)
        elif k.startswith('AL_MAP_LUT'):
            drivers[w['o']]=(k,p,w,0,'o')
        elif k in ['EG_PHY_MSLICE','EG_PHY_LSLICE']:
            for port in ['f','fx']:
                for lane,o in enumerate(reversed(bits(w.get(port,'')))):
                    if o:drivers[o]=(k,p,w,lane,port)
    def ev(net):
        if net in memo:return memo[net]
        if net=="1'b0":return 0
        if net=="1'b1" or net.startswith('open_n'):return allmask
        assert net in drivers,('No combinational driver',net)
        info=drivers[net]
        if info[0]=='buf':value=ev(info[1])
        else:
            kind,p,w,lane,port=info
            def inp(pin):
                bb=list(reversed(bits(w[pin]))) if pin in w else ["1'b1"]*2
                return ev(bb[lane])
            if kind.startswith('AL_MAP_LUT'):
                width=int(kind[10:]);inputs=[ev(w[x]) for x in 'abcdef'[:width]];init=p['INIT'][1]
            else:
                assert p.get('MODE','"LOGIC"')=='"LOGIC"',(net,info)
                assert port=='f',(net,kind,port)
                inputs=[inp(x) for x in 'abcd']
                if kind=='EG_PHY_MSLICE':init=p.get(f'INIT_LUT{lane}',('number',0))[1]
                else:
                    fi=p.get(f'INIT_LUTF{lane}',('number',0))[1];gi=p.get(f'INIT_LUTG{lane}',('number',0))[1]
                    mux=p.get(f'LSFMUX{lane}','"LUTF"')
                    if mux=='"FUNC5"':inputs.append(inp('e'));init=fi|(gi<<16)
                    elif mux=='"LUTF"':init=fi
                    elif mux=='"LUTG"':init=gi
                    else:raise AssertionError((net,mux))
            value=0
            for index in range(1<<len(inputs)):
                if not(init>>index&1):continue
                term=allmask
                for bit,x in enumerate(inputs):term &= x if index>>bit&1 else allmask^x
                value|=term
        memo[net]=value;return value
    ev.has=lambda net:net in memo or net in drivers
    return ev

gray=[]
prefix='\\media/layers/prefetch/'
for name,width,outname in [('rb2',9,'retired_b'),('rf2',9,'retired_f')]:
    mask=(1<<(1<<width))-1
    initial={}
    for i in range(width):
        n=prefix+name+f'_reg[{i}]';kind,p,w=sg[n];assert kind=='AL_MAP_SEQ'
        initial[w['q']]=sum(((j>>i)&1)<<j for j in range(1<<width))
    # Packing removes transparent synthesis aliases. Bind all names of each
    # source Q to the same truth vector, without assuming a physical cell name.
    changed=True
    while changed:
        changed=False
        for kind,p,w in sg.values():
            if kind!='buf':continue
            for o,i in zip(bits(w['o']),bits(w['i'])):
                if o in initial and i not in initial:initial[i]=initial[o];changed=True
                if i in initial and o not in initial:initial[o]=initial[i];changed=True
                if o in initial and i in initial:assert initial[o]==initial[i]
    synth_ev=evaluator(sg,initial,mask);phy_ev=evaluator(g,initial,mask)
    checked=[];folded=[]
    for i in range(width):
        net=prefix+outname+f'[{i}]'
        if not synth_ev.has(net):
            assert not phy_ev.has(net),('New unmatched standalone decoder net',net)
            folded.append(i)
            continue
        assert synth_ev(net)==phy_ev(net),('Packed Gray truth differs',net)
        checked.append(i)
    assert checked
    gray.append({'source':name,'outputs':outname,'bits':width,'input_vectors':1<<width,
                 'checked_live_standalone_bits':checked,'no_standalone_net_after_synthesis':folded,
                 'method':'Mapped RTL truth versus actual packed LUT INIT and wiring, all source-Q combinations for live standalone decode outputs; folded consumers are covered by retained mapping and final STA, not this truth test'})
result={'pass':True,'build':str(B),'native_RAM_INIT_unchanged':True,
        'BG_native9K':6,'FG_native32K':2,'BG_24bit_depth':2048,'FG_32bit_depth':1024,
        'gray_decoders':gray,'scope':'New physical object; functional/CDC lifetime evidence remains separately bounded'}
(B/'v121_native_audit.json').write_text(json.dumps(result,indent=2)+'\n')
(R/'reports/V124_NATIVE_A.json').write_text(json.dumps(result,indent=2)+'\n')
print('V121_NATIVE_A_PASS',B,flush=True)
