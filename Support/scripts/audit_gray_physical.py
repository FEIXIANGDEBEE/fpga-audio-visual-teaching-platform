from pathlib import Path
import sys,json

from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1]
B=Path(sys.argv[1]) if len(sys.argv)>1 else Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
ALL=(1<<8192)-1
vectors=[sum(((i>>b)&1)<<i for i in range(8192)) for b in range(13)]
sg=graph((B/'synthesized.v').read_text())
g=graph((B/'routed.v').read_text());drivers={}
for name,(kind,params,ports) in g.items():
    if kind=='buf':drivers[ports['o']]=(kind,params,ports,0,name)
    elif kind in ['EG_PHY_MSLICE','EG_PHY_LSLICE']:
        for port in ['f','fx']:
            for lane,out in enumerate(reversed(bits(ports.get(port,'')))):
                if out:drivers[out]=(kind,params,ports,lane,name,port)
result=[];failures=[]
for bank in range(2):
    for direction,source in [('read','rg2'),('write','wg2')]:
        prefix=f'\\banks/fifo{bank}/';memo={prefix+source+f'[{b}]':vectors[b] for b in range(13)}
        def ev(net):
            if net in memo:return memo[net]
            if net=="1'b0":return 0
            if net=="1'b1" or net.startswith('open_n'):return ALL
            info=drivers[net];kind,params,ports,lane,name=info[:5]
            if kind=='buf':val=ev(ports['i'])
            else:
                assert info[5]=='f' and params.get('MODE','"LOGIC"')=='"LOGIC"',(net,info)
                def inp(pin):
                    bs=list(reversed(bits(ports[pin]))) if pin in ports else ["1'b1"]*2
                    return ev(bs[lane])
                ins=[inp(p) for p in 'abcd']
                if kind=='EG_PHY_MSLICE':init=params.get('INIT_LUT'+str(lane),('number',0))[1]
                else:
                    init=params.get('INIT_LUTF'+str(lane),('number',0))[1]
                    mux=params.get('LSFMUX'+str(lane),'"LUTF"')
                    assert mux in ['"LUTF"','"FUNC5"'],info
                    if mux=='"FUNC5"':assert init==params.get('INIT_LUTG'+str(lane),('number',0))[1],info
                val=0
                for index in range(16):
                    if not(init>>index&1):continue
                    term=ALL
                    for j,value in enumerate(ins):term &= value if index>>j&1 else ALL^value
                    val |= term
            memo[net]=val;return val
        checked=[]
        # Track the canonical last XOR output from synthesis. Pass-through
        # stages may alias a binary bit to an earlier prefix stage's net.
        for b in range(13):
            stages=[ps for ps in range(4) if b+(1<<ps)<=12]
            if stages:
                ps=max(stages);suffix='$'+('r' if direction=='read' else 'w')+'_xor'
                candidates=[ports['o'] for name,(kind,params,ports) in sg.items() if name.startswith(prefix+f'g_gray_stage[{ps}]$g_bit[{b}]$') and name.endswith(suffix)]
                assert len(candidates)==1,candidates
                net=candidates[0]
            else:net=prefix+source+f'[{b}]'
            want=0
            for k in range(b,13):want ^= vectors[k]
            got=ev(net);checked.append(b)
            if got!=want:
                bad=got^want;first=(bad&-bad).bit_length()-1
                failures.append({'bank':bank,'direction':direction,'output_bit':b,'first_bad_gray':first,'bad_inputs':bad.bit_count()})
        assert len(checked)==13,(bank,direction,checked)
        result.append({'bank':bank,'direction':direction,'live_final_bits':checked,'gray_inputs_each':8192})
r={'pass':not failures,'build':str(B),'cases':result,'failures':failures,'method':'Physical packed LUT INIT and actual port wiring; 8192-vector bitset truth evaluation, not EQN text'}
(B/'physical_gray_truth.json').write_text(json.dumps(r,indent=2)+'\n')
(R/'reports/GRAY_PHYSICAL.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r),flush=True)
sys.exit(0 if r['pass'] else 1)
