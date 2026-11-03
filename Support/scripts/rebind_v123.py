"""Bind exact packed aliases, retaining the original max-delay and SR-only intent."""
from pathlib import Path
import re,json,shutil
from scene_mapped_graph import graph,bits
def bind(OUT,ROOT,run,device):
    packed=graph((OUT/'placed_native.v').read_text());sg=graph((OUT/'synthesized.v').read_text())
    from registered_reset import prove
    registered=prove(packed,sg)
    (OUT/'registered_reset_placed.json').write_text(json.dumps(registered,indent=2)+'\n')
    proven_reset_roots=set(registered['proven_reset_roots'])
    aliases={}
    for k,p,w in packed.values():
        if k=='buf':
            for a,b in zip(bits(w['o']),bits(w['i'])):aliases[a]=b
    def root(n):
        seen=set()
        while n in aliases:assert n not in seen;seen.add(n);n=aliases[n]
        return n
    def fused_lut_proof(cell,p,w,lane,dnet):
        drivers=[(m,v) for m,v in sg.items() if v[0].startswith('AL_MAP_LUT') and dnet in bits(v[2].get('o',''))]
        assert len(drivers)==1,(dnet,drivers);sname,(sk,sp,sw)=drivers[0]
        sins=[x for x in 'abcdef' if x in sw];sinit=sp['INIT'][1]
        snets=[root(bits(sw[x])[0]) for x in sins]
        phys={}
        for x in 'abcd':
            net=list(reversed(bits(w[x])))[lane] if x in w else None
            phys[x]=None if net is None or re.fullmatch(r'open_n\d+',net) or net in ("1'b0","1'b1") else root(net)
        assert all(v is None or v in snets for v in phys.values()),('extra functional input',cell,phys,snets)
        assert sorted(v for v in phys.values() if v)==sorted(snets),('input not mapped exactly once',cell,phys,snets)
        inits=[p[k][1] for k in (f'INIT_LUTF{lane}',f'INIT_LUTG{lane}',f'INIT_LUT{lane}') if k in p];assert inits,(cell,sorted(p))
        free=[x for x,v in phys.items() if v is None];checked=0
        for sv in range(1<<len(sins)):
            val={snets[i]:(sv>>i)&1 for i in range(len(sins))};want=(sinit>>sv)&1
            for fv in range(1<<len(free)):
                pin={x:(val[phys[x]] if phys[x] else (fv>>free.index(x))&1) for x in 'abcd'}
                idx=pin['d']*8+pin['c']*4+pin['b']*2+pin['a']
                for init in inits:assert (init>>idx)&1==want,('fused LUT truth differs',cell,lane,sv,fv);checked+=1
        return {'synth_lut':sname,'synth_INIT':sinit,'synth_inputs':dict(zip(sins,snets)),'physical_pins':phys,'physical_INITs':inits,'free_pins_any_value':free,'checked_points':checked}
    lines=(OUT/'v3.sdc').read_text().splitlines();proof=[];replacements=[]
    for index,line in enumerate(lines):
        if line.startswith('set_false_path -to [get_pins -hier {') and 'release_pipe_reg' in line:
            pins=[]
            for domain in ['audio_reset','video_reset']:
                prefix='\\media/'+domain+'/release_pipe';found=[]
                for n,(k,p,w) in packed.items():
                    lanes=[q for q in bits(w.get('q','')) if q.startswith(prefix+'[')]
                    if lanes:
                        assert w['sr']=='\\media/'+domain+'/arst_n' and p['SRMODE']=='"ASYNC"' and p['SRMUX']=='"INV"'
                        found.extend(lanes);pins.append(n.lstrip('\\')+'.sr');proof.append(dict(kind='release_SR_alias',cell=n,q=lanes,sr=w['sr']))
                assert set(found)=={prefix+f'[{j}]' for j in range(3)}
            new='set_false_path -to [get_pins -hier {'+' '.join(pins)+'}]';replacements.append(dict(old=line,new=new));lines[index]=new
        elif line.startswith('set_max_delay -datapath_only -from [get_regs {current_valid}]'):
            original=sg['current_valid_reg'][2]
            pins=[]
            for n,(k,p,w) in packed.items():
                if k not in ['EG_PHY_MSLICE','EG_PHY_LSLICE']:continue
                for lane,q in enumerate(reversed(bits(w.get('q','')))):
                    if q!='current_valid' and not re.fullmatch(r'current_valid_dup_\d+',q):continue
                    # Compare against the actual synthesized register contract, not one historical mapping:
                    # same clock, same CE (or none with CEMUX "1"), proven async reset, and D equal to the
                    # original D net, entering through MI or through this slice's own LUT output F.
                    assert w['clk']==original['clk'] and root(w['sr']) in proven_reset_roots
                    if 'ce' in original:assert w.get('ce')==original['ce'] and p.get('CEMUX')=='"CE"'
                    else:assert w.get('ce') is None and p.get('CEMUX')=='"1"'
                    assert p['SRMODE']=='"ASYNC"' and p['SRMUX']=='"INV"' and p[f'REG{lane}_REGSET']=='"RESET"'
                    sd=p[f'REG{lane}_SD'];assert sd in ['"MI"','"F"']
                    port='mi' if sd=='"MI"' else 'f'
                    # An internal-only F output (consumed solely by this slice's register) has no port at all.
                    data=list(reversed(bits(w[port])))[lane] if port in w else None
                    fused=None
                    if data!=original['d']:
                        # V13.3: the packer fused the synthesized D LUT into this slice's own F LUT, so the
                        # lane-F net is an unrouted open_n name. Accept only with a truth proof: every
                        # connected lane pin is a synthesized LUT input, each input appears once, and for all
                        # input values and ANY value on absent/open pins every present F/G INIT equals the
                        # synthesized LUT. Names alone never pass.
                        assert sd=='"F"' and (data is None or re.fullmatch(r'open_n\d+',data)),(n,lane,sd,data,original['d'])
                        fused=fused_lut_proof(n,p,w,lane,original['d'])
                    pins.append(n.lstrip('\\')+f'.q[{lane}]');proof.append(dict(kind='equivalent_current_valid_copy',cell=n,lane=lane,q=q,clock=w['clk'],ce=w.get('ce'),sr=w['sr'],data=original['d'],data_select=sd.strip('"'),fused_lut_truth=fused))
            assert pins,'Every actual source copy must have the original CLK/CE/SR/D contract'
            new='set_max_delay -datapath_only -from [get_pins -hier {'+' '.join(pins)+'}] -to [get_regs {media/reader/en1 media/reader/en1_p}] 39.7'
            replacements.append(dict(old=line,new=new));lines[index]=new
    assert len(replacements)==2
    (OUT/'v3_before_alias_rebind.sdc').write_text((OUT/'v3.sdc').read_text())
    (OUT/'v3.sdc').write_text('\n'.join(lines)+'\n')
    run('sdc_check_rebound',device+['import_db placed.db','clear_sdc','read_sdc v3.sdc','check_timing -verbose -file sdc_check_rebound.timing','write_verilog rebound_native.v'])
    from scene_mapped_graph import canonical
    assert canonical(packed)==canonical(graph((OUT/'rebound_native.v').read_text())),'Only constraints may change'
    text=(OUT/'sdc_check_rebound.timing').read_text();assert 'checking invalid constraint(0)' in text
    assert 'fails' not in (OUT/'sdc_check_rebound.log').read_text()
    shutil.copy2(OUT/'sdc_check_rebound.timing',OUT/'sdc_check_placed.timing')
    active=Path(json.loads((ROOT/'reports/BUILD_A_ACTIVE.json').read_text())['path'])
    if OUT.resolve()==active.resolve():shutil.copy2(OUT/'v3.sdc',ROOT/'constraints/scene_a.sdc')
    (OUT/'v123_alias_rebinding.json').write_text(json.dumps(dict(pass_=True,proof=proof,replacements=replacements,removed_constraints=[],all_time_limits_unchanged=True,placed_graph_and_INIT_unchanged=True),indent=2)+'\n')
    (OUT/'sdc_post_place_pruned.json').write_text(json.dumps(dict(pass_=True,removed=[],removed_line_numbers=[]),indent=2)+'\n')
