"""V15 bounded A placement alternatives; reuse qualified R1 protected netlist.

User authorized multiple routes on 2026-11-02. Only seed changes. Each lane
has 2400 s and the existing stagnation rule. No synthesis or hardware access.
"""
from pathlib import Path
import sys, json, shutil, subprocess, time, re
from scene_mapped_graph import graph, canonical
from rebind_v123 import bind

ROOT = Path(__file__).resolve().parents[1]
BASE = Path('D:/aidownload/anlu_main/main1/V15_1_low_power/build_a')
SEED = int(sys.argv[1]); assert SEED in (5, 7)
OUT = BASE.parent / f'route_a_seed{SEED}'
RESUME='--resume' in sys.argv
assert RESUME or not OUT.exists(), 'Never overwrite an attempted lane'
assert (BASE/'STOP_route.json').exists(), 'Only start after the current attempt fails/stops'
OUT.mkdir(exist_ok=RESUME)
for f in ['protected.db','protected.v','synthesized.v','native_guard.json',
          'source_initial.sdc','place_pins.tcl']:
    if RESUME:assert (BASE/f).read_bytes()==(OUT/f).read_bytes(),f
    else:shutil.copy2(BASE/f,OUT/f)
if not RESUME:shutil.copy2(OUT/'source_initial.sdc',OUT/'v3.sdc')
START = time.monotonic() - max(0,time.time()-OUT.stat().st_ctime)
TD = 'D:/apps/anlogic/bin/td_commands_prompt.exe'
def save(name, obj):
    (OUT/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
save('LANE.json',dict(source=str(BASE),seed=SEED,only_variable='place seed',
     wall_budget_seconds=2400,hardware_accessed=False))
def run(name, lines):
    # Limit even read-only TD timer initialization to the documented 8 threads.
    # import_db restores saved settings, so set the thread bound AFTER import.
    import_index=next(i for i,l in enumerate(lines) if l.startswith('import_db '))
    lines = lines[:import_index+1]+['set_param flow thread 8']+lines[import_index+1:]
    (OUT/(name+'.tcl')).write_text('\n'.join(lines)+f'\nputs V3_{name.upper()}_DONE\n')
    with (OUT/(name+'.log')).open('w',encoding='utf-8') as log:
        p=subprocess.Popen([TD],cwd=OUT,stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,text=True)
        p.stdin.write(f'source {name}.tcl\nexit\n');p.stdin.close()
        save('RUNNING.json',dict(pid=p.pid,stage=name,seed=SEED))
        while p.poll() is None:
            try:p.wait(timeout=2)
            except subprocess.TimeoutExpired:pass
            reason=None;rows=[]
            if name=='route':
                log.flush();s=(OUT/'route.log').read_text(errors='replace')
                tail=re.split(r'\nPHY-1001 : Stage [\d.]+ \| Rip-up And ReRoute\n',s)[-1]
                rows=[(int(i),int(n),float(t)) for i,n,t in re.findall(r'Iter (\d+):.*?over cnt = (\d+).*?time\(s\) = ([\d.]+)',tail)]
                if rows:
                    best=min(rows,key=lambda x:x[1]);last=rows[-1]
                    if best[1]>0 and last[0]-best[0]>=10 and last[1]>best[1] and last[2]>=max(30,best[2]*1.5):
                        reason='route stagnation: >=10 iterations without lower conflicts, rebound and slower iteration'
            if time.monotonic()-START>2400:reason='explicit 2400 second lane budget'
            if (OUT/'CANCEL_REQUESTED.json').exists():reason='another lane fully signed off; bounded attempts stopped'
            if reason:
                subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],capture_output=True)
                p.wait(timeout=30)
                save('STOP_'+name+'.json',dict(status='ACTIVELY_ABORTED',reason=reason,qualified=False,route_iterations=rows))
                raise RuntimeError(reason)
    s=(OUT/(name+'.log')).read_text(errors='replace')
    assert p.returncode==0 and f'V3_{name.upper()}_DONE' in s and not re.search(r'\b(ERROR|FATAL)\b',s),s[-2000:]
    print('DONE',SEED,name,flush=True)

device=['import_device eagle_s20.db -package EG4S20BG256']
pins=[l for l in (OUT/'place_pins.tcl').read_text().splitlines() if l.strip() and not l.lstrip().startswith('#')]
if not RESUME:run('place',device+['import_db protected.db','read_sdc v3.sdc',
    'set_param flow qor_monitor off','set_param place effort high',f'set_param place seed {SEED}',
    'set_inst_assignment {media/memory/memory/u2_ram/u2_wrrd/sdr_t_reg} {location = x21y34z1;}']+pins+[
    'report_param -all -detail -file effective_place_parameters.txt','place','update_timing -mode manhattan',
    'report_area -io_info -file placed.area','write_verilog placed_native.v','export_db placed.db'])
parameters=(OUT/'effective_place_parameters.txt').read_text()
thread_setting=re.search(r'^\s*thread\s*\|\s*(\w+)\s*\|',parameters,re.M)[1]
assert thread_setting=='8' or (RESUME and thread_setting=='auto')
save('THREAD_SETTINGS.json',dict(placement_setting=thread_setting,placement_global_iteration_threads=32 if thread_setting=='auto' else 8,route_requested_threads=8,
    deviation='Initial placement import_db restored auto (32 in log); completed placement retained; route sets 8 after import' if thread_setting=='auto' else None))
assert re.search(r'^\s*seed\s*\|\s*'+str(SEED)+r'\s*\|',parameters,re.M)
g=graph((OUT/'placed_native.v').read_text())
assert sum(k=='EG_PHY_MSLICE' for k,p,w in g.values())<=4900
bind(OUT,ROOT,run,device)
assert json.loads((OUT/'sdc_post_place_pruned.json').read_text())['removed']==[]
run('route',device+['import_db placed.db','clear_sdc','read_sdc v3.sdc',
    'set_param flow qor_monitor off','set_param route effort routability','set_param route priority timing','set_param route fix_hold off',
    'report_param -all -detail -file effective_route_parameters.txt','route','update_timing -mode final',
    'write_verilog before_hold.v','export_sdc_target -file before_hold.sdc','report_timing_summary -file before_hold.timing',
    'fix_hold','update_timing -mode final','write_verilog routed.v','export_sdc_target -file effective.sdc','export_db routed.db',
    'report_area -io_info -file routed.area','report_io -verbose -file io.txt','report_timing_summary -file final.timing',
    'check_timing -verbose -file check.timing','report_route_status -drc -file route_status.txt'])
g=graph((OUT/'routed.v').read_text())
assert canonical(graph((OUT/'before_hold.v').read_text()))==canonical(g)
assert (OUT/'before_hold.sdc').read_bytes()==(OUT/'effective.sdc').read_bytes()
t=(OUT/'final.timing').read_text()
setup=float(re.search(r'SWNS:\s*([-+\d.]+)ns',t)[1]);hold=float(re.search(r'HWNS:\s*([-+\d.]+)ns',t)[1])
report=dict(board='a',setup_wns_ns=setup,hold_wns_ns=hold,native_mslice=sum(k=='EG_PHY_MSLICE' for k,p,w in g.values()),
    native_lslice=sum(k=='EG_PHY_LSLICE' for k,p,w in g.values()),native_guard_branches=json.loads((OUT/'native_guard.json').read_text())['registered_branches'],
    phase='physical_pending_audit',hardware_accessed=False,place_strategy='default',place_seed=SEED)
report['pass']=setup>=0 and hold>=0 and report['native_mslice']<=4900
save('physical.json',report);print(json.dumps(report),flush=True)
assert report['pass'],'Physical timing/capacity gate failed'
