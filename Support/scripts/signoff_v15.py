from pathlib import Path
import sys,json,re,subprocess
from scene_mapped_graph import graph,bits,canonical
R=Path(__file__).resolve().parents[1];role=sys.argv[1]
B=Path(json.loads((R/f'reports/BUILD_{role.upper()}_ACTIVE.json').read_text())['path'])
def save(name,v):(R/'reports'/name).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def call(n,*args):
 log=B/(n+'.audit.log')
 completed_reports={'audit_v15_memory.py':'V15_FFT_MEMORY_NATIVE.json','audit_eco_reset_native.py':'V15_ECO_RESET_NATIVE.json','audit_v151_routed.py':'V151_ROUTED_POWER.json'}
 if n in completed_reports:
  path=R/'reports'/completed_reports[n]
  if path.exists():
   prior=json.loads(path.read_text())
   if prior.get('pass') and Path(prior.get('build',''))==B:
    print('REUSE',n,flush=True);return
 # A completed invocation belongs to this immutable build directory only.
 if log.exists() and log.read_text(errors='replace').startswith('EXIT=0\n'):
  print('REUSE',n,flush=True);return
 p=subprocess.run([sys.executable,'-B',str(R/'scripts'/n),*args],capture_output=True,text=True,encoding='utf-8')
 log.write_text(f'EXIT={p.returncode}\n'+p.stdout+p.stderr,encoding='utf-8');print(n,p.returncode,p.stdout[-200:],flush=True)
 assert p.returncode==0,p.stderr
physical=json.loads((B/'physical.json').read_text());assert physical['pass']
assert physical['native_mslice']<=4820 and physical['setup_wns_ns']>0 and physical['hold_wns_ns']>0
route=(B/'route.log').read_text();timing=(B/'final.timing').read_text();check=(B/'check.timing').read_text()
assert re.findall(r'over cnt\s*=\s*(\d+)',route)[-1]=='0' and 'V3_ROUTE_DONE' in route
assert 'No multi-drive.' in route and 'No abnormal timing path.' in route
for k in ['STNS','HTNS']:assert float(re.search(k+r':\s*([-+\d.]+)ns',timing)[1])==0
assert float(re.search(r'STA coverage\s+:\s*([\d.]+)%',timing)[1])==100
for label in ['no clock','clock definition','invalid constraint','combinational loops','soft fifo timing exception constraints','no path constraints','shadowed/ignored timing exception constraints']:
 assert f'checking {label}(0)' in check,label
pll_detail=check.split('5. checking PLL/buffer clocks.')[1].split('6. checking combinational loops.')[0]
assert not re.search(r'There are [1-9]\d* (?:clock pins|clocks)',pll_detail),pll_detail
clocklocal=re.search(r'(\d+) clock net\(s\) utilize local routing resource',route)
assert (int(clocklocal[1]) if clocklocal else 0)<=(2 if role=='a' else 0)
g=graph((B/'routed.v').read_text());pg=graph((B/'protected.v').read_text());sg=graph((B/'synthesized.v').read_text())
assert {n:(k,p) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM')}=={n:(k,p) for n,(k,p,w) in pg.items() if k.startswith('EG_PHY_BRAM')}
assert canonical(graph((B/'before_hold.v').read_text()))==canonical(g)
assert sum(k=='EG_PHY_MSLICE' for k,p,w in g.values())<=4820
adc=(R/f'constraints/scene_{role}.adc').read_text();pins=dict(re.findall(r'set_pin_assignment\s+\{\s*(\S+)\s*\}\s*\{\s*LOCATION\s*=\s*(\w+);',adc))
actual={n:ball for n,d,ball in re.findall(r'^\s*(\S+)\s+(INPUT|OUTPUT|INOUT)\s+(\S+)\s+(?:LVCMOS|LVDS)\w*',(B/'routed.area').read_text(),re.M)}
assert all(actual.get(k)==v for k,v in pins.items()),'pins'
call('audit_release.py',role,'routed')
if role=='a':
 call('audit_registered_reset_physical.py');call('audit_polish.py','routed');call('audit_v121_a.py',str(B))
else:
 for n,args in [('audit_owner_cache.py',['routed']),('audit_image_ram.py',['routed']),('audit_gray_physical.py',[]),('audit_reset_compact_physical.py',[]),('audit_shared_memory.py',['routed']),('audit_owner_routed.py',[]),('audit_registered_active.py',[]),('audit_algorithm_routed.py',[]),('audit_replay_source.py',[]),('audit_witness.py',[]),('audit_crc_shared.py',[]),('audit_v1011_boot.py',[]),('audit_v127_native.py',['routed'])]:call(n,*args)
call('audit_v3.py',role)
objects=(B/'stage_objects.txt').read_text();stages=[]
for i,(a,b) in enumerate(re.findall(r'STAGE \d+ (\d+) (\d+)',objects)):
 a,b=int(a),int(b)
 if not a and not b:stages.append({'stage':i,'status':'pruned'});continue
 assert a and b,(i,a,b)
 t=(B/f'stage_{i}.timing').read_text();slacks=[float(v) for v in re.findall(r'^Slack\s+:\s*([-+\d.]+)ns',t,re.M)]
 assert slacks and min(slacks)>=0,(i,slacks)
 assert 'Check Type          : setup' in t and 'Check Type          : hold' in t
 stages.append({'stage':i,'source':a,'dest':b,'min_slack':min(slacks)})
native={}
if role=='b':
 call('audit_v15_memory.py')
 call('audit_eco_reset_native.py')
 call('audit_v151_routed.py')
 plls=[(n,p,w) for n,(k,p,w) in g.items() if k=='EG_PHY_PLL'];assert len(plls)==1
 n,p,w=plls[0];assert p['STDBY_ENABLE']=='"ENABLE"' and w.get('stdby') not in [None,"1'b0","1'b1"]
 assert w.get('reset') not in [None,"1'b0","1'b1"]
 sleep_read=[]
 for n,(k,p,w) in g.items():
  if k.startswith('EG_PHY_BRAM') and ('analysis/fft/real_ram/' in n or 'analysis/fft/imag_ram/' in n or 'analysis/fft/g_coefficients' in n):
   controls={a:v for a,v in w.items() if a in ['cea','ceb','csa','csb']}
   assert controls,(n,'no RAM enables')
   sleep_read.append({'cell':n,'controls':controls,'params':{a:v for a,v in p.items() if 'MUX' in a and ('CE' in a or 'CS' in a)}})
 assert len(sleep_read)>=4
 native={'pll':plls,'fft_memories':sleep_read,'new_reset_sync_instances':['eco_sys_reset','eco_audio_reset','screen/source_reset'],'V151_power_audit':'reports/V151_ROUTED_POWER.json','reset_chains_and_stages':'reports/V15_ECO_RESET_NATIVE.json; 7 chains, 14 setup/hold stage paths','behavioral_reset_and_wake':'V151_DIRECTED_TESTS.json plus unchanged V15 screen/policy reuse; PLL analog relock not hardware measured'}
physical['phase']='offline_signed_off'
save(f'OFFLINE_SIGNOFF_{role.upper()}.json',{'pass':True,'build':str(B),'physical':physical,'STA_coverage':100,'TNS_THS':0,'conflicts':0,'pins':len(pins),'native_RAM_INIT_preserved':True,'CDC_stages':stages,'low_power_native':native,'hardware_accessed':False,'power_measured':False})
(B/'artifacts').mkdir(exist_ok=True)
from audit_v3 import run
if '--no-bitgen' not in sys.argv and not (B/f'artifacts/scene_{role}.bit').exists():run(B,'bitgen',['import_device eagle_s20.db -package EG4S20BG256','import_db routed.db',f'bitgen -bit {{{(B/f"artifacts/scene_{role}.bit").as_posix()}}} -gen_mask -unused_io_status none'])
print('OFFLINE_SIGNOFF_PASS_NO_BITGEN' if '--no-bitgen' in sys.argv else 'OFFLINE_SIGNOFF_AND_BITGEN_PASS',role,flush=True)
