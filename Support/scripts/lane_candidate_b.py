from pathlib import Path
import sys,time,json,shutil,subprocess,re
from scene_mapped_graph import graph,canonical
R=Path(__file__).resolve().parents[1];ROOT=Path('D:/aidownload/anlu_main/aaa_comment_rework_20261103');BASE=ROOT/'build_b_final'
seed=int(sys.argv[1]);assert seed in (3,5,7)
OUT=ROOT/f'route_b_seed{seed}';assert not OUT.exists(),'Never overwrite an attempted lane';OUT.mkdir()
TD='D:/apps/anlogic/bin/td_commands_prompt.exe';start=time.monotonic()
for name in ('protected.db','protected.v','synthesized.v','native_guard.json','reset_distribution.json','source_initial.sdc'):
 shutil.copy2(BASE/name,OUT/name)
shutil.copy2(OUT/'source_initial.sdc',OUT/'v3.sdc')
def save(n,d):(OUT/n).write_text(json.dumps(d,indent=2)+'\n')
save('LANE.json',dict(seed=seed,source=str(BASE),only_variable='place seed',threads=8,budget_seconds=2400,hardware_accessed=False))
def run(name,lines):
 lines=[x for line in lines for x in ([line,'set_param flow thread 8'] if line.startswith('import_db ') else [line])]
 (OUT/(name+'.tcl')).write_text('\n'.join(lines)+f'\nputs V3_{name.upper()}_DONE\n')
 with (OUT/(name+'.log')).open('w') as log:
  p=subprocess.Popen([TD],cwd=OUT,stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,text=True)
  p.stdin.write(f'source {name}.tcl\nexit\n');p.stdin.close();save('RUNNING.json',dict(stage=name,pid=p.pid,seed=seed))
  while p.poll() is None:
   try:p.wait(timeout=2)
   except subprocess.TimeoutExpired:pass
   reason=None;rows=[]
   if name=='route':
    log.flush();s=(OUT/'route.log').read_text(errors='replace')
    s=re.split(r'\nPHY-1001 : Stage [\d.]+ \| Rip-up And ReRoute\n',s)[-1]
    rows=[(int(i),int(n),float(t)) for i,n,t in re.findall(r'Iter (\d+):.*?over cnt = (\d+).*?time\(s\) = ([\d.]+)',s)]
    if rows:
     best=min(rows,key=lambda x:x[1]);last=rows[-1]
     if best[1]>0 and last[0]-best[0]>=10 and last[1]>best[1] and last[2]>=max(30,best[2]*1.5):reason='stagnation: no new best for10 iterations, rebound, slower'
   if time.monotonic()-start>2400:reason='2400 second lane budget'
   if (OUT/'CANCEL_REQUESTED.json').exists():reason='first fully qualified lane accepted; remaining bounded route stopped'
   if reason:
    subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],capture_output=True);p.wait(timeout=30)
    save('STOP_'+name+'.json',dict(status='ACTIVELY_ABORTED',reason=reason,qualified=False,iterations=rows));raise RuntimeError(reason)
 s=(OUT/(name+'.log')).read_text(errors='replace')
 assert p.returncode==0 and f'V3_{name.upper()}_DONE' in s and not re.search(r'\b(ERROR|FATAL)\b',s),(name,s[-2500:])
 print('LANE_DONE',seed,name,flush=True)
d=['import_device eagle_s20.db -package EG4S20BG256']
try:
 run('place',d+['import_db protected.db','read_sdc v3.sdc','set_param flow qor_monitor off','set_param place effort high',f'set_param place seed {seed}','report_param -all -detail -file effective_place_parameters.txt','place','update_timing -mode manhattan','report_area -io_info -file placed.area','write_verilog placed_native.v','export_db placed.db'])
 t=(OUT/'effective_place_parameters.txt').read_text();assert re.search(r'^\s*thread\s*\|\s*8\s*\|',t,re.M) and re.search(r'^\s*seed\s*\|\s*'+str(seed)+r'\s*\|',t,re.M)
 g=graph((OUT/'placed_native.v').read_text());ms=sum(k=='EG_PHY_MSLICE' for k,p,w in g.values());assert ms<=4820,ms
 area=(OUT/'placed.area').read_text()
 for key,limit in [('bram32k',11),('bram9k',41),('dsp',7),('pll',1)]:assert int(re.search(r'^\s*#'+key+r'\s+(\d+)',area,re.M)[1])<=limit,(key,area[-3000:])
 # Rebind reset-only endpoints to actual packed SR ports, restoring original Gray limits.
 pins=[n.lstrip('\\')+'.sr' for n,(k,p,w) in g.items() if ('release_pipe_reg' in n or '/release_pipe' in w.get('q','')) and 'sr' in w];assert pins
 bound='\n'.join(l for l in (OUT/'v3.sdc').read_text().splitlines() if not ('set_false_path -to [get_pins' in l and ('release_pipe_reg' in l or 'heartbeat_reset/' in l)))+'\n'
 for bank in ('fifo0','fifo1'):
  for first,source in [('rg1','rg'),('wg1','wg')]:
   for suffix in ('[*]','*'):bound=bound.replace(f'set_false_path -to [get_regs {{banks/{bank}/{first}{suffix}}}]\n','')
   bound+=f'set_max_delay -datapath_only -from [get_regs {{banks/{bank}/{source}[*]}}] -to [get_regs {{banks/{bank}/{first}[*]}}] 19.7\n'
 bound+='set_false_path -to [get_pins -hier {'+' '.join(pins)+'}]\n';(OUT/'preroute_bound.sdc').write_text(bound)
 run('bind_before_route',d+['import_db placed.db','clear_sdc','read_sdc preroute_bound.sdc','update_timing -mode manhattan','check_timing -verbose -file preroute_checks.timing','write_verilog preroute_native.v','export_db preroute_bound.db'])
 check=(OUT/'preroute_checks.timing').read_text()
 for label in ('invalid constraint','soft fifo timing exception constraints','no clock','clock definition','combinational loops'):assert f'checking {label}(0)' in check,label
 assert canonical(g)==canonical(graph((OUT/'preroute_native.v').read_text()))
 save('preroute_binding_proof.json',dict(pass_=True,SR_only_pins=pins,placed_graph_and_INIT_identical=True,original_Gray19_7ns=True))
 run('route',d+['import_db preroute_bound.db','set_param flow qor_monitor off','set_param route effort routability','set_param route priority timing','set_param route fix_hold off','report_param -all -detail -file effective_route_parameters.txt','route','update_timing -mode final','write_verilog before_hold.v','export_sdc_target -file before_hold.sdc','report_timing_summary -file before_hold.timing','fix_hold','update_timing -mode final','write_verilog routed.v','export_sdc_target -file effective.sdc','export_db routed.db','report_area -io_info -file routed.area','report_io -verbose -file io.txt','report_timing_summary -file final.timing','check_timing -verbose -file check.timing','report_route_status -drc -file route_status.txt'])
 g=graph((OUT/'routed.v').read_text());assert canonical(graph((OUT/'before_hold.v').read_text()))==canonical(g)
 assert (OUT/'before_hold.sdc').read_bytes()==(OUT/'effective.sdc').read_bytes()
 t=(OUT/'final.timing').read_text();setup=float(re.search(r'SWNS:\s*([-+\d.]+)ns',t)[1]);hold=float(re.search(r'HWNS:\s*([-+\d.]+)ns',t)[1])
 report=dict(board='b',setup_wns_ns=setup,hold_wns_ns=hold,native_mslice=sum(k=='EG_PHY_MSLICE' for k,p,w in g.values()),native_lslice=sum(k=='EG_PHY_LSLICE' for k,p,w in g.values()),native_guard_branches=json.loads((OUT/'native_guard.json').read_text())['registered_branches'],phase='physical_pending_audit',hardware_accessed=False,place_strategy='default',place_seed=seed)
 report['pass']=setup>0 and hold>0 and report['native_mslice']<=4820;save('physical.json',report);assert report['pass'],report
 print('LANE_PHYSICAL_PASS',seed,json.dumps(report),flush=True)
except BaseException as e:
 save('LANE_FAILURE.json',dict(failure=repr(e),hardware_accessed=False));raise
