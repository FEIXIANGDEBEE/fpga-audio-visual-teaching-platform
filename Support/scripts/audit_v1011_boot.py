"""V10.11 changed object: verified-first-image boot gate in the actual netlists.

Proves on synthesized and routed objects that the new SYS-domain state
(`boot_pause`, `verifying`, `scan_done`) exists with its clock, and that the
service's boot-transfer input is the image transmitter's `file_done` level
(not a pulse and not the catalogue completion).  Functional ordering is covered
by TEST_V1011.json; this audit only binds that logic to the physical object.

Routed netlists pack/rename FFs, so the register is located by its Q net and
its clock pin rather than by the synthesis cell name.
"""
from pathlib import Path
import json
from scene_mapped_graph import graph, bits
R = Path(__file__).resolve().parents[1]
B = Path(json.loads((R / 'reports/BUILD_B_ACTIVE.json').read_text())['path'])
result = {'pass': True, 'build': str(B), 'phases': {}}
for phase in ('synthesized', 'routed'):
    g = graph((B / (phase + '.v')).read_text())
    def driver(net):
        rows = []
        for n, (k, p, w) in g.items():
            for port in ('q', 'f', 'fx'):
                lanes = list(reversed(bits(w.get(port, ''))))
                if net in lanes:
                    rows.append((n, k, p, w, port, lanes.index(net)))
        if phase == 'synthesized':
            rows = [x for x in rows if x[1] != 'buf']
        else:
            rows = [x for x in rows if x[1] in ('EG_PHY_MSLICE', 'EG_PHY_LSLICE')]
        return rows
    rows = {}
    for name in ('boot_pause', 'verifying', 'scan_done'):
        net = '\\files/files/' + name
        d = driver(net)
        assert len(d) == 1, (phase, name, d[:3])
        n, k, p, w, port, lane = d[0]
        assert w.get('clk') == 'sys_clk_dup_1', (phase, name, n, w.get('clk'))
        loads = [(m, pin) for m, (kk, pp, ww) in g.items() for pin, v in ww.items()
                 if pin not in ('q', 'f', 'fx', 'o') and net in bits(v)]
        rows[name] = {'driver': n, 'kind': k, 'port': port, 'lane': lane, 'clock': w['clk'], 'Q': net, 'loads': len(loads)}
    done = '\\image/file_done'
    d = driver(done)
    assert len(d) == 1, (phase, 'image file_done', d[:3])
    n, k, p, w, port, lane = d[0]
    assert w.get('clk') == 'sys_clk_dup_1', (phase, 'image file_done clock', w.get('clk'))
    rows['image_file_done'] = {'driver': n, 'kind': k, 'port': port, 'lane': lane, 'clock': w['clk']}
    boot_cells = {m for m in g if m.startswith('\\files/files/')}
    bridge = [(m, pin) for m, (kk, pp, ww) in g.items() if m in boot_cells for pin, v in ww.items()
              if pin not in ('q', 'f', 'fx', 'o') and done in bits(v)]
    pause_loads = [(m, pin) for m, (kk, pp, ww) in g.items() if m in boot_cells for pin, v in ww.items()
                   if pin not in ('q', 'f', 'fx', 'o') and '\\files/files/boot_pause' in bits(v)]
    if phase == 'routed' and (not bridge or not pause_loads):
        # Packing can give a shared physical slice an unrelated cell name.
        # Require both signals on the SAME LUT lane, an actual files/files
        # output, and truth-table dependence on both inputs.
        found=[]
        for m,(kind,par,wires) in g.items():
            if kind not in ('EG_PHY_LSLICE','EG_PHY_MSLICE'): continue
            for lane in (0,1):
                def at(pin):
                    lanes=list(reversed(bits(wires.get(pin,''))))
                    return lanes[lane] if len(lanes)>lane else None
                ins=[at(k) for k in ('a','b','c','d')];out=at('f')
                if done not in ins or '\\files/files/boot_pause' not in ins or not out or not out.startswith('\\files/files/'):continue
                # MSLICE names its ordinary LUTs INIT_LUT0/1; LSLICE uses
                # INIT_LUTF0/1. Both must prove same-lane truth dependence.
                param=par.get(('INIT_LUT' if kind=='EG_PHY_MSLICE' else 'INIT_LUTF')+str(lane))
                if not (isinstance(param,tuple) and param[0]=='number'):continue
                truth=param[1]
                def depends(k):return any(((truth>>v)&1)!=((truth>>(v^(1<<k)))&1) for v in range(16))
                if depends(ins.index(done)) and depends(ins.index('\\files/files/boot_pause')):
                    found.append((m,lane,out,ins,truth))
        assert found, (phase,'no packed same-lane dependent boot-pause and image-done bridge')
        bridge=found;pause_loads=found
    assert bridge, (phase, 'image/file_done does not reach the file service')
    assert pause_loads, (phase, 'boot_pause is not consumed by the service next-state logic')
    rows['bridge_detail']=bridge[:4]
    rows['image_done_bridges_to_service'] = len(bridge)
    rows['boot_pause_next_state_loads'] = len(pause_loads)
    result['phases'][phase] = rows
(R / 'reports/BOOT_GATE_NATIVE.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('V1011_BOOT_GATE_NATIVE_PASS', json.dumps({k: len(v) for k, v in result['phases'].items()}), flush=True)
