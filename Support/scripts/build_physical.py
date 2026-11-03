"""V10.11 B: resume the sealed synthesis DB; native protection + fixed-seed physical flow only.
No synthesis, board programming, TF or Flash commands.
"""
from pathlib import Path
import json,sys,subprocess,re,copy,shutil,datetime,time,os
from scene_mapped_graph import graph,canonical,inventory,replace_bit
ROOT=Path(__file__).resolve().parents[1]
BOARD=sys.argv[1];assert BOARD in ('a','b')
SYN=json.loads((ROOT/f'reports/SYNTHESIS_{BOARD.upper()}.json').read_text());assert SYN['pass']
assert not (Path(SYN['path'])/'SOURCE_INVALIDATED.json').exists(),'Superseded source: no physical qualification'

TD=r'D:\apps\anlogic\bin\td_commands_prompt.exe'

# Bounded draw mode, same documented exception as V10.8/V10.9: V111_BUILD_DIR
# points at a copy of the *same* protected netlist and constraints so independent
# placement draws can be recorded. The netlist, guard, constraints and every gate
# stay the candidate's; a draw that routes is re-audited from its own database.
OUT=Path(SYN['path'])
DRAW=bool(os.environ.get('V111_BUILD_DIR'))
assert not DRAW,'V11.6 uses one documented fixed-seed candidate, not inherited draw mode'
assert (OUT/'synthesized.v').exists() and (OUT/f'scene_{BOARD}_top_Runs/syn_1/scene_{BOARD}_top_gate.db').exists()
FORCE='--replace' in sys.argv
assert not FORCE,'A repeated physical run requires new failure analysis and authorization'
# Deviation recorded explicitly (2026-10-26 23:40, user instruction "多换方法,
# 不要死循环"): placement is deterministic for a fixed seed, so the C2 netlist
# reproduced the identical 107-conflict wall in two independent attempts. The
# placer seed is therefore made selectable here so a different placement basin
# can be explored without touching RTL, constraints, timing gates, or the
# router settings. Every other gate stays identical; a seed change cannot fake
# any evidence because the routed object is fully re-audited and re-signed.
SEED=6 if BOARD=='a' else 5
assert 'V111_PLACE_SEED' not in os.environ,'V12.4 one fixed seed per board'
LABEL=os.environ.get('V111_ARCHIVE_LABEL',f'seed{SEED}')
# Documented flow option (2026-10-27): the vendor ships a congestion-reduction
# placement strategy in doc/strategies/official_strategy_ph1.json. C2 is 95.0%
# full and the fixed-seed placer reproducibly parks an unroutable 107-conflict
# pocket, so the official "CongestionHigh" parameter set is applied verbatim
# instead of drawing another seed. Netlist, seed, constraints, audits and every
# timing/DRC gate are unchanged; only the placer's congestion objective changes.
CONGESTION_HIGH=[('opt_timing','high'),('ofv','70'),('opt_max_density','50'),
 ('target_density','0.6'),('target_density_pp','0.7'),('aggressive_opt','20'),
 ('enhanced_beeline_opt','2'),('enhanced_gp','on'),('non_crit_opt','on'),
 ('post_place_opt','high'),('enable_congestion_recovery','on')]
STRATEGY=os.environ.get('V111_PLACE_STRATEGY','')
assert STRATEGY=='','V11.6 initial placement uses the baseline strategy'
if FORCE:
    import shutil as _sh
    arc=OUT/f'route_stopped_{LABEL}';arc.mkdir(exist_ok=True)
    for n in ['placed.db','placed_native.v','placed.area','place.log','congestion.congo','preroute_bound.db','preroute_native.v','preroute_checks.timing','preroute_binding_proof.json','bind_before_route.log','bind_before_route.tcl','route.log','route.tcl','STOP_route.json','route_status.txt']:
        src=OUT/n
        if src.exists(): _sh.move(str(src),str(arc/n))
assert FORCE or not (OUT/'placed.db').exists(),'Placement already exists; resume the completed stage, never repeat unchanged work'
def save(name,value): (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def run(name,lines):
 p=OUT/(name+'.tcl');p.write_text('\n'.join(lines)+f'\nputs V3_{name.upper()}_DONE\n',encoding='utf-8')
 with (OUT/(name+'.log')).open('w',encoding='utf-8') as log:
  process=subprocess.Popen([TD],cwd=OUT,stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,text=True)
  process.stdin.write(f'source {name}.tcl\nexit\n');process.stdin.close()
  start=time.monotonic();reason=None;rows=[]
  while process.poll() is None:
   try:process.wait(timeout=2)
   except subprocess.TimeoutExpired:pass
   if name=='route':
    log.flush();current=(OUT/'route.log').read_text(errors='replace')
    rows=[(int(i),int(n),float(t)) for i,n,t in re.findall(r'Iter (\d+):.*?over cnt = (\d+).*?time\(s\) = ([\d.]+)',re.split(r'\nPHY-1001 : Stage [\d.]+ \| Rip-up And ReRoute\n',current)[-1])]
    if rows:
     best=min(rows,key=lambda x:x[1]);last=rows[-1]
     if best[1]>0 and last[0]-best[0]>=10 and last[1]>best[1] and last[2]>=max(30,best[2]*1.5):reason='route stagnation: >=10 iterations without lower conflicts, rebound and slower iteration'
   budget=2400.0
   # R1 deviation, recorded explicitly: C2 stopped on the 1200 s budget (not on
   # the stagnation rule) while still descending 137->107 over 16 iterations, so
   # the same candidate was not proven stagnant. Only the wall-clock allowance is
   # raised here; the stagnation rule, seed, constraints and every correctness
   # gate are unchanged.
   if time.monotonic()-physical_start>budget:reason='explicit wall time budget'
   if reason:
    subprocess.run(['taskkill.exe','/PID',str(process.pid),'/T','/F'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    process.wait(timeout=30)
    save('STOP_'+name+'.json',{'status':'ACTIVELY_ABORTED','stage':name,'reason':reason,'elapsed_seconds':time.monotonic()-start,'route_iterations':rows,'qualified':False})
    raise RuntimeError(name+' actively stopped: '+reason)
  result=process
  result=process
 s=(OUT/(name+'.log')).read_text(errors='replace')
 errors=[l for l in s.splitlines() if re.search(r'\b(ERROR|FATAL)\b|HDL-7225|undeclared symbol',l) and not re.search(r"undeclared symbol '(?:\*\*|PLL_HDMI_AUDIO_open\d+)'",l)]
 if result.returncode or f'V3_{name.upper()}_DONE' not in s or errors: raise RuntimeError(name+': '+repr(errors[-8:])+s[-600:])
 print('DONE',BOARD,name,flush=True)
physical_start=time.monotonic()
device=['import_device eagle_s20.db -package EG4S20BG256']
top='scene_'+BOARD+'_top'
if True:
 g=graph((OUT/'synthesized.v').read_text());want=copy.deepcopy(g);branches=inventory(g)
 selected=[]
 if BOARD=='a':
  # Diagnosed A short paths: end_status bus and read_errors diagnostic bus.
  # Protect their direct held-data D branches as complete buses so placement
  # does not trade the original violation for the adjacent bit. No cycles change.
  selected=[]
  for sink,(kind,params,ports) in g.items():
   net=ports.get('d','')
   if kind=='AL_MAP_SEQ' and (('/fx_diagnostics/held_data_reg' in sink and net.startswith('end_status[')) or
     ('/video_diagnostic/held_data_reg' in sink and '/reader/read_errors[' in net)):
    drivers=[n for n,(k,p,w) in g.items() if k=='AL_MAP_SEQ' and w.get('q')==net]
    assert len(drivers)==1,(sink,net)
    selected.append(dict(source=net,driver=drivers[0],sinks=[dict(cell=sink,port='d',lane=0,width=1,net=net)]))
  # 2026-10-27 diagnostic-frame compaction: end_status and read_errors moved
  # behind a narrower select, so these two D nets no longer exist under their
  # diagnosed names. A partial bus match would protect one bit and leave its
  # neighbours exposed, so the extension is applied only when the complete
  # original set is present. New D nets are covered by final STA/hold/DRC.
  if len(selected)!=35:
   print(f'DIAGNOSED_BUS_BRANCHES_PARTIAL {len(selected)}/35: extension skipped, '
         'new D nets are covered by final STA/hold/DRC',flush=True)
   selected=[]
  branches+=selected
 if BOARD=='b':
  from reset_distribution import inventory as reset_inventory
  reset_limit=json.loads((ROOT/'config/NATIVE_RESET_LAYOUT.json').read_text())['maximum_group_sr_ports']
  extra=reset_inventory(g,group_limit=reset_limit);start=len(branches);branches+=extra
  save('reset_distribution.json',{'pass':True,'source':'analysis/reset/release_pipe[2]','buffers':len(extra),'sinks':sum(len(x['sinks']) for x in extra),
   'maximum_group_fanout':reset_limit,'sequential_cycles_changed':False,'branches':[dict(x,net='v3_ram_guard_'+str(start+i)) for i,x in enumerate(extra)]})
 DONOR_COUNT=1024 if BOARD=='a' else 512
 assert len(branches)<=DONOR_COUNT
 q=lambda s:'{'+s.lstrip('\\')+'}'
 donors=['\\g_native_hold['+str(i)+']$u_buf' for i in range(DONOR_COUNT)]
 driver='\\led_q_reg[0]';assert driver in g
 finalnet=g[donors[-1]][2]['o']
 lines=device+[f'import_db ./{top}_Runs/syn_1/{top}_gate.db']
 # Validate the imported donor table before any mutation. A transient TD
 # lookup failure previously returned empty pins and crashed disconnect_net.
 lines += ['set donor_check [get_cells -hier {*g_native_hold*}]',f'if {{[llength $donor_check]!={DONOR_COUNT}}} {{error {{Donor import inventory mismatch}}}}']
 # Disconnect every donor from the temporary LED chain first.
 for cell in donors:
  assert g[cell][0]=='AL_MAP_LUT1' and g[cell][1]=={'EQN':'"(A)"','INIT':('number',2)}
  lines += [f'set pa [get_pins -hier {q(cell+".a")}]',f'set po [get_pins -hier {q(cell+".o")}]',
   'if {[llength $pa]!=1 || [llength $po]!=1} {error {Donor pins absent before disconnect}}',
   'disconnect_net -net [get_nets -of $pa] -objects $pa','disconnect_net -net [get_nets -of $po] -objects $po']
 lines += [f'set pd [get_pins -hier {q(driver+".q")}]','disconnect_net -net [get_nets -of $pd] -objects $pd',f'connect_net -net {q(finalnet)} -objects $pd']
 want[driver][2]['q']=finalnet
 for i,b in enumerate(branches):
  cell=donors[i];net='v3_ram_guard_'+str(i)
  want[cell][2].update(a=b['source'],o=net)
  lines += [f'set pa [get_pins -hier {q(cell+".a")}]',f'set po [get_pins -hier {q(cell+".o")}]',f'create_net {net}']
  for j,s in enumerate(b['sinks']):
   pin=s['cell']+'.'+s['port']+(f'[{s["lane"]}]' if s['width']>1 else '')
   lines += ['set pb {}',f'foreach candidate [get_pins -hier {q(pin)}] {{if {{$candidate eq {q(pin)}}} {{lappend pb $candidate}}}}','if {[llength $pb]!=1} {error {Exact branch pin absent or ambiguous}}','set old [get_nets -of $pb]']
   if j==0:lines+=['set source_net $old','connect_net -net $old -objects $pa',f'connect_net -net {net} -objects $po']
   else:lines+=['if {$source_net ne $old} {error {RAM source alias mismatch}}']
   lines += ['disconnect_net -net $old -objects $pb',f'connect_net -net {net} -objects $pb']
   p=want[s['cell']][2];p[s['port']]=replace_bit(p[s['port']],s['lane'],net)
 for cell in donors[len(branches):]:lines += [f'remove_cell {q(cell)}'];del want[cell]
 lines+=['write_verilog protected.v','export_db protected.db']
 if not (OUT/'native_guard.json').exists():run('protect',lines)
 assert canonical(graph((OUT/'protected.v').read_text()))==canonical(want),'Native graph/INIT guard delta differs'
 save('native_guard.json',{'pass':True,'registered_branches':len(branches),'unused_donors_removed':DONOR_COUNT-len(branches),'other_cells_and_INIT_unchanged':True,'branches':branches,'diagnosed_bus_branches':len(selected)})
 # Explicit applied endpoint inventory; absent optional paths are recorded, not fabricated.
 base='media' if BOARD=='a' else 'screen'
 cdc=[base+'/video_diagnostic/request_sync[0]',base+'/video_diagnostic/ack_sync[0]',base+'/observer/observed_m',
      base+'/mem_ready_meta',base+'/memory/req0_s1',base+'/memory/client0/rsp_sync1'] if BOARD=='a' else ['screen/snapshot/request_sync[0]','screen/snapshot/ack_sync[0]']
 bounds=[]
 if BOARD=='a':
  bounds += [('media/memory/client0/m_req_addr* media/memory/client0/m_req_data* media/memory/client0/m_req_dm* media/memory/client0/m_req_write','media/memory/req_addr_r* media/memory/req_data_r* media/memory/req_dm_r* media/memory/req_write_r',23.7),
  ('media/memory/rsp0_data* media/memory/rsp0_error','media/memory/client0/rsp_data* media/memory/client0/rsp_error',19.7),
  ('media/video_diagnostic/held_data*','media/video_diagnostic/snapshot*',19.7),('media/observer/observed_id*','media/observer/committed',19.7),
  ('display_base*','media/reader/frame_base*',39.7),('display_id*','media/reader/frame_id*',39.7),('display_base_crc*','media/reader/frame_crc*',39.7),
  ('display_swap','media/reader/swap_p1',39.7),('current_valid state*','media/reader/en1 media/reader/en1_p',39.7)]
  for a,b in [('clean_epoch','clean1'),('frame_epoch','epoch1'),('rflush','rflush_m1'),('frame_base*','base_q*'),('read_errors*','read_fault_p1')]:bounds.append(('media/reader/'+a,'media/reader/'+b,19.7))
  for x in ['wr_to_rd_cross_inst','rd_to_wr_cross_inst']:bounds.append((f'media/reader/fifo/fifo_core/{x}/primary_addr_gray_reg*',f'media/reader/fifo/fifo_core/{x}/sync_r1*',19.7))
 else:bounds=[('screen/snapshot/held_data*','screen/snapshot/snapshot*',39.7)]
 if BOARD=='a':
  cdc += ['media/picture_fx/brightness_m[*]','media/picture_fx/contrast_m[*]','media/settings_snapshot/request_sync[0]','media/settings_snapshot/ack_sync[0]','media/fx_configuration/request_sync[0]','media/fx_configuration/ack_sync[0]','media/fx_diagnostics/request_sync[0]','media/fx_diagnostics/ack_sync[0]','media/fade/commit_sync1','media/fade/done_sync1','media/fade/start_sync1','media/audio_snapshot/request_sync[0]','media/audio_snapshot/ack_sync[0]']
  bounds += [('media/settings_snapshot/held_data*','media/settings_snapshot/snapshot*',39.7),('media/fx_configuration/held_data*','media/fx_configuration/snapshot*',39.7),('media/fx_diagnostics/held_data*','media/fx_diagnostics/snapshot*',19.7),('transition_base*','media/reader/frame_new_base*',39.7),('transition_id*','media/reader/frame_new_id*',39.7),('transition_crc*','media/reader/frame_new_crc*',39.7),('active_effect*','media/reader/frame_mode*',39.7),('swap_pending','media/reader/pending_p1',39.7),('media/audio_snapshot/held_data*','media/audio_snapshot/snapshot*',19.7)]
  cdc += ['media/subtitle_snapshot/request_sync[0]','media/subtitle_snapshot/ack_sync[0]']
  cdc += ['media/geometry_snapshot/request_sync[0]','media/geometry_snapshot/ack_sync[0]']
  bounds += [('media/geometry_snapshot/held_data*','media/geometry_snapshot/snapshot*',39.7)]
  bounds += [('media/subtitle_snapshot/held_data*','media/subtitle_snapshot/snapshot*',19.7)]
  # Frozen V12.3 diagnosis: frame_new_id is declared/assigned but has no
  # consumer in the unchanged reader. Require the new mapped object also has
  # no such endpoint; retain transition -> display_id -> frame_id timing.
  assert not any('/reader/frame_new_id' in n for n in g)
  bounds=[(a,b,n) for a,b,n in bounds if b!='media/reader/frame_new_id*']
 else:
  cdc += ['microphone/hb1','microphone/samples/ack1','microphone/samples/req1','microphone/diagnostics/request_sync[0]','microphone/diagnostics/ack_sync[0]','active_m','uf_m','banks/guard/hb1','banks/ab1','banks/r01','banks/r11',
   'banks/commands/ack1','banks/commands/req1','analysis/pcm/ack1','analysis/pcm/req1','analysis/ov1',
   'banks/playback_snapshot/request_sync[0]','banks/playback_snapshot/ack_sync[0]',
   'witness_snapshot/request_sync[0]','witness_snapshot/ack_sync[0]',
   'screen/audio_snapshot/request_sync[0]','screen/audio_snapshot/ack_sync[0]']
  bounds += [('microphone/samples/held*','microphone/samples/ddata*',19.7),('microphone/diagnostics/held_data*','microphone/diagnostics/snapshot*',19.7),('banks/commands/held*','banks/commands/ddata*',81.0),('analysis/pcm/held*','analysis/pcm/ddata*',19.7),
   ('banks/playback_snapshot/held_data*','banks/playback_snapshot/snapshot*',19.7),
   ('witness_snapshot/held_data*','witness_snapshot/snapshot*',19.7),
   ('screen/audio_snapshot/held_data*','screen/audio_snapshot/snapshot*',39.7)]
  cdc += ['recorder/play_commands/ack1','recorder/play_commands/req1','recorder/stop_meta','banks/borrow_meta','history_ready_meta']
  bounds += [('recorder/play_commands/held*','recorder/player/command',81.0)]
  cdc += ['banks/volume_commands/ack1','banks/volume_commands/req1','banks/volume_snapshot/request_sync[0]','banks/volume_snapshot/ack_sync[0]']
  bounds += [('banks/volume_commands/held*','banks/volume_commands/ddata*',81.0),('banks/volume_snapshot/held_data*','banks/volume_snapshot/snapshot*',19.7)]
  for bank in ['fifo0','fifo1']:
   for source,dest in [('rg','rg1'),('wg','wg1')]:bounds.append((f'banks/{bank}/{source}*',f'banks/{bank}/{dest}*',19.7))
 if BOARD=='a':
  cdc += ['media/layer_fault_diag/meta','media/safe_m1','media/layer_snapshot/request_sync[0]','media/layer_snapshot/ack_sync[0]',
   'media/layers/fault_m1','media/layers/prefetch/pb1[*]','media/layers/prefetch/pf1[*]']
  cdc += ['media/layer_diag_snapshot/request_sync[0]','media/layer_diag_snapshot/ack_sync[0]']
  bounds += [('media/layer_diag_snapshot/held_data*','media/layer_diag_snapshot/snapshot*',19.7)]
  bounds += [('media/layer_snapshot/held_data*','media/layer_snapshot/snapshot*',39.7),
   ('media/layers/prefetch/frame_toggle','media/layers/prefetch/epoch_m1',19.7),
   ('media/layers/prefetch/bg_ret_gray*','media/layers/prefetch/rb1*',19.7),
   ('media/layers/prefetch/fg_ret_gray*','media/layers/prefetch/rf1*',19.7),
   ('media/layers/prefetch/bg_tag* media/layers/prefetch/bg_epoch*','media/layers/prefetch/pt_bg* media/layers/prefetch/pe_bg*',39.7),
   ('media/layers/prefetch/fg_tag* media/layers/prefetch/fg_epoch*','media/layers/prefetch/pt_fg* media/layers/prefetch/pe_fg*',39.7),
   ('media/layers/frame_enable','media/layers/prefetch/active',19.7)]
 sdc=['create_clock -name SYS -period 20.000 [get_ports {sys_clk}]','derive_clocks',
 'set_false_path -from [get_ports {sys_rst_n uart_rx key1 key2 key3 sw1 sw2 sw3 sw4 '+('r_data[*] r_clk r_valid f_ready audio_bclk audio_lrck audio_data' if BOARD=='a' else 'f_data[*] f_clk f_valid r_ready sd_miso mic_sd')+'}]']
 if BOARD=='b':sdc += ['create_clock -name MCLK -period 81.333333 [get_ports {audio_mclk}]']
 # Release removes only the pure debug CDC producers named in PLAN.md.
 # Replay progress is retained under its new 32-bit publisher hierarchy.
 if BOARD=='b':
  cdc=[p.replace('witness_snapshot/','replay_counter/snapshot/') for p in cdc]
  bounds=[(a.replace('witness_snapshot/','replay_counter/snapshot/'),b.replace('witness_snapshot/','replay_counter/snapshot/'),n) for a,b,n in bounds]
 removed_debug=['media/video_diagnostic/','media/fx_diagnostics/','media/subtitle_snapshot/'] if BOARD=='a' else []
 intentional=[]
 kept=[]
 for path in cdc:
  if any(path.startswith(prefix) for prefix in removed_debug):intentional.append({'kind':'false_path','objects':path})
  else:kept.append(path)
 cdc=kept;kept=[]
 for a,b,n in bounds:
  if any(a.startswith(prefix) or b.startswith(prefix) for prefix in removed_debug):intentional.append({'kind':'max_delay','from':a,'to':b,'old_limit_ns':n})
  else:kept.append((a,b,n))
 bounds=kept
 save('removed_debug_constraints.json',{'intentional_debug_cones':removed_debug,'removed':intentional,'remaining_timing_limits_unchanged':True})
 # Literal collections are required: TD stores constraint expressions;
 # reusing Tcl $va/$vb would bind all deferred constraints to the last values.
 def literal_bus(pat):
  return ' '.join(p[:-1]+'[*]' if p.endswith('*') and '[' not in p else p for p in pat.split())
 # Remove optional paths eliminated by constant inactive effect logic.
 if BOARD=='a':
  cdc=[p for p in cdc if p!='media/memory/req1_s1']
  bounds=[(a,b,n) for a,b,n in bounds if not a.startswith('current_valid state')]
  bounds.append(('current_valid','media/reader/en1 media/reader/en1_p',39.7))
 # 2026-10-27: prune constraints whose objects no longer exist. The compacted
 # diagnostic frames removed the subtitle snapshot CDC registers, so their
 # set_false_path/set_max_delay objects are absent and TD reports an invalid
 # constraint. Every dropped entry is recorded; a large drop would mean a real
 # structural change and has to be reviewed instead of silently accepted.
 prot_graph=graph((OUT/'protected.v').read_text())
 def _rx(p):
  p=p.replace('[*]','\x01')
  return re.compile('^'+re.escape(p).replace(r'\*','.*').replace(r'\?','.').replace('\x01',r'\[\d+\]')+'$')
 # TD resolves get_regs {x[i]} to the mapped register x_reg[i]; normalise the
 # _reg suffix so existence is judged on the same names the constraint uses.
 _regs=[re.sub(r'_reg(?=\[|$)','',n.lstrip('\\')) for n in prot_graph]
 def _exists(pattern):
  names=[_rx(part) for part in pattern.split()]
  return any(r.match(n) for n in _regs for r in names)
 pruned=[]
 # Inventory only. Missing mapped names may be aliases; do not silently remove
 # any data-path constraint because get_regs cannot find its old spelling.
 for p in cdc:
  if not _exists(p):pruned.append(dict(kind='false_path',objects=p))
 for t in bounds:
  if not (_exists(t[0]) and _exists(t[1])):pruned.append(dict(kind='max_delay',from_=t[0],to=t[1]))
 save('sdc_name_inventory.json',{'unresolved_by_cell_name':pruned,'constraints_removed':False})
 for pat in cdc:sdc += [f'set_false_path -to [get_regs {{{pat}}}]']
 for i,(a,b,n) in enumerate(bounds):
  sdc += [f'set_max_delay -datapath_only -from [get_regs {{{literal_bus(a)}}}] -to [get_regs {{{literal_bus(b)}}}] {n}']
 if BOARD=='b':sdc += ['set_false_path -from [get_ports {ir_rx}]']
 # Lock inputs and reset-only crossings. No blanket false-clock group.
 for pat in (['media/video_clock/pll_inst.extlock','media/memory/pll/pll_inst.extlock','media/audio_clock/pll_inst.extlock'] if BOARD=='a' else ['screen/pll/pll_inst.extlock']):
  sdc += [f'set_false_path -from [get_pins {{{pat}}}]']
 if BOARD=='a':
  for pat in ['media/video_reset/arst_n','media/reader/fifo/fifo_rst']:
   sdc += [f'set_false_path -through [get_nets -hier {{{pat}}}]']
 if BOARD=='a':
  sdc += ['set_false_path -through [get_nets -hier {media/audio_reset_n}]']
 else:
  for pat in ['banks/guard/reset_source','banks/bank_run[*]','audio_rst_n','banks/wrst_n','recorder/srst_n','recorder/drst_n']:
   sdc += [f'set_false_path -through [get_nets -hier {{{pat}}}]']
 # Only asynchronous reset pins of domain release synchronizers. SYS-synchronous
 # logic and every release-pipe D/Q stage remain timed normally.
 gg=prot_graph
 reset_pins=[n.lstrip('\\')+'.sr' for n,(kind,params,ports) in gg.items() if ('release_pipe_reg' in n or '/release_pipe' in ports.get('q','')) and 'sr' in ports]
 if reset_pins:sdc += ['set_false_path -to [get_pins -hier {'+' '.join(reset_pins)+'}]']
 (OUT/'v3.sdc').write_text('\n'.join(sdc)+'\n')
 reviewed=OUT/'reviewed_pre_place.sdc'
 if reviewed.exists():shutil.copy2(reviewed,OUT/'v3.sdc')
 # 2026-10-27: TD is the authority on which constraint objects survive. Two
 # subtitle-snapshot synchronizer bits are still present as cells but have become
 # dummy nodes (their consumers were removed with the compacted diagnostic
 # frames), so get_regs cannot bind them. Ask the tool, drop exactly the lines it
 # rejects, then require a clean re-check; nothing is guessed from names alone.
 check_lines=device+['import_db protected.db','set_param flow thread 8','read_sdc v3.sdc','check_timing -verbose -file sdc_check.timing']
 run('sdc_check',check_lines)
 first=(OUT/'sdc_check.log').read_text(errors='replace')
 shutil.copy2(OUT/'sdc_check.timing',OUT/'sdc_check_first.timing')
 failed=sorted({int(m) for m in re.findall(r'v3\.sdc\((\d+)\) fails',first)})
 if failed:
  original=(OUT/'v3.sdc').read_text().splitlines()
  save('sdc_binding_failure.json',{'pass':False,'line_numbers':failed,'lines':[original[i-1] for i in failed],'action':'Stop before placement. Diagnose actual drivers/consumers, preserve original timing, then save reviewed_pre_place.sdc with evidence.'})
  raise RuntimeError('SDC binding needs evidence-based review before placement; no lines automatically removed')
 else:
  save('sdc_pruned_lines.json',{'pass':True,'removed_line_numbers':[],'removed':[]})
 assert 'checking invalid constraint(0)' in (OUT/'sdc_check.timing').read_text(errors='replace'),'invalid constraint remains'
 if not DRAW:shutil.copy2(OUT/'v3.sdc',ROOT/f'constraints/phys_{BOARD}.sdc')
 shutil.copy2(OUT/'v3.sdc',OUT/'source_initial.sdc')
 lines=device+['import_db protected.db','read_sdc v3.sdc','set_param flow qor_monitor off','set_param flow thread 8','set_param place effort high',f'set_param place seed {SEED}']
 if STRATEGY=='congestion_high':
  lines += [f'set_param place {k} {v}' for k,v in CONGESTION_HIGH]
 if BOARD=='a':lines += ['set_inst_assignment {media/memory/memory/u2_ram/u2_wrrd/sdr_t_reg} {location = x21y34z1;}']
 # R1: 46/46 native macros pinned to the proven V10.7 C7 routed floorplan. No
 # seed change, no netlist change here; only the floorplan anchor is inherited.
 pins=OUT/'place_pins.tcl'
 if pins.exists():lines += [l for l in pins.read_text().splitlines() if l.strip() and not l.lstrip().startswith('#')]
 lines += ['report_param -all -detail -file effective_place_parameters.txt','place','update_timing -mode manhattan','report_area -io_info -file placed.area','export_congo_file -step place -file congestion.congo','write_verilog placed_native.v','export_db placed.db']
 run('place',lines)
 parameters=(OUT/'effective_place_parameters.txt').read_text()
 assert re.search(r'^\s*thread\s*\|\s*8\s*\|',parameters,re.M), '8-thread limit not effective'
 assert re.search(r'^\s*seed\s*\|\s*'+str(SEED)+r'\s*\|',parameters,re.M), 'seed not effective'
 # 2026-10-27: placement removes a few objects that still bound before place (the
 # unused subtitle synchronizer bits and the mapped release-pipe reset pins). The
 # delivered A parent (V10.9) ran with exactly those two classes unapplied and
 # reported them as invalid constraints. Ask the tool on the placed database and
 # drop precisely what it rejects, so the routed object carries only constraints
 # that bind and check.timing is clean instead of inheriting dead ones.
 if BOARD=='a':
  from rebind_v123 import bind
  bind(OUT,ROOT,run,device)
 placed_text=(OUT/'placed.area').read_text()
 for metric,limit in [('bram32k',11 if BOARD=='b' else 16),('bram9k',64),('dsp',7 if BOARD=='b' else 29),('pll',1 if BOARD=='b' else 3)]:
  assert int(re.search(r'^\s*#'+metric+r'\s+(\d+)',placed_text,re.M)[1])<=limit,('pre-route capacity',metric)
 placed_graph=graph((OUT/'placed_native.v').read_text())
 assert sum(k=='EG_PHY_MSLICE' for k,p,w in placed_graph.values())<=4900,'V12.9 design hard capacity4900 for both boards'
 if BOARD=='a' and OUT.name in ['build_a_c4','build_a_c5']:
  actual_mslice=sum(k=='EG_PHY_MSLICE' for k,p,w in placed_graph.values())
  variant='A4' if OUT.name=='build_a_c4' else 'A5'
  save(variant+'_PLACEMENT_VERDICT.json',{'pass':actual_mslice<4759,'phase':'PLACED_NOT_FINAL_ROUTED','A2_same_seed5_placed_mslice':4759,'actual_placed_mslice':actual_mslice,'net_placed_mslice_saved':4759-actual_mslice,'new_RTL':'Atlas row address reduction; same feature specification'})
  assert actual_mslice<4759,'No whole-board placement reduction versus A2 seed5: stop before route'
 if BOARD=='a':
  removed=json.loads((OUT/'sdc_post_place_pruned.json').read_text())['removed']
  assert not any('layers/prefetch' in line or 'layer_snapshot' in line for line in removed), ('P2 constraint disappeared',removed)
  bound=(OUT/'v3.sdc').read_text()
  for x in ['bg_ret_gray[*]}] -to [get_regs {media/layers/prefetch/rb1[*]}]', 'prefetch/rf1','prefetch/frame_toggle','prefetch/bg_tag','prefetch/fg_tag','layer_diag_snapshot']:
   assert x in bound, ('P2 constraint absent',x)
 route_db='placed.db'
 if BOARD=='b':
  packed=graph((OUT/'placed_native.v').read_text())
  physical_pins=[n.lstrip('\\')+'.sr' for n,(k,p,w) in packed.items() if ('release_pipe_reg' in n or '/release_pipe' in w.get('q','')) and 'sr' in w]
  assert physical_pins
  bound='\n'.join(line for line in (OUT/'v3.sdc').read_text().splitlines() if not ('set_false_path -to [get_pins' in line and ('release_pipe_reg' in line or 'heartbeat_reset/' in line)))+'\n'
  for bank in ['fifo0','fifo1']:
   for first,source in [('rg1','rg'),('wg1','wg')]:
    for suffix in ['[*]','*']:bound=bound.replace(f'set_false_path -to [get_regs {{banks/{bank}/{first}{suffix}}}]\n','')
    bound+=f'set_max_delay -datapath_only -from [get_regs {{banks/{bank}/{source}[*]}}] -to [get_regs {{banks/{bank}/{first}[*]}}] 19.7\n'
  bound+='set_false_path -to [get_pins -hier {'+' '.join(physical_pins)+'}]\n'
  (OUT/'preroute_bound.sdc').write_text(bound)
  run('bind_before_route',device+['import_db placed.db','clear_sdc','read_sdc preroute_bound.sdc','update_timing -mode manhattan','check_timing -verbose -file preroute_checks.timing','write_verilog preroute_native.v','export_db preroute_bound.db'])
  before_route=(OUT/'preroute_checks.timing').read_text()
  for label in ['invalid constraint','soft fifo timing exception constraints','no clock','clock definition','combinational loops']:
   assert f'checking {label}(0)' in before_route,label
  assert canonical(packed)==canonical(graph((OUT/'preroute_native.v').read_text()))
  save('preroute_binding_proof.json',{'pass':True,'SR_only_pins':physical_pins,'placed_graph_and_INIT_identical':True,'data_constraints_unchanged_except_explicit_Gray19_7ns_restoration':True,'new_synthesis_or_placement':False,'invalid_constraints':0,'soft_fifo_exception_errors':0})
  route_db='preroute_bound.db'
 # A: route re-reads the reviewed v3.sdc so the routed object carries exactly the
 # constraints that bind after placement (the db still stores the place-time set,
 # which contained the objects placement removed). B uses its own bound database.
 route_prefix=['clear_sdc','read_sdc v3.sdc'] if BOARD=='a' else []
 lines=device+['import_db '+route_db]+route_prefix+['set_param flow qor_monitor off','set_param flow thread 8','set_param route effort routability','set_param route priority timing','set_param route fix_hold off',
 'report_param -all -detail -file effective_route_parameters.txt','route','update_timing -mode final','write_verilog before_hold.v','export_sdc_target -file before_hold.sdc','report_timing_summary -file before_hold.timing',
 'fix_hold','update_timing -mode final','write_verilog routed.v','export_sdc_target -file effective.sdc','export_db routed.db',
 'report_area -io_info -file routed.area','report_io -verbose -file io.txt','report_timing_summary -file final.timing','check_timing -verbose -file check.timing','report_route_status -drc -file route_status.txt']
 if STRATEGY=='congestion_high':
  lines.insert(5,'set_param route post_route_opt high')
 run('route',lines)
 pg=graph((OUT/'routed.v').read_text());assert canonical(graph((OUT/'before_hold.v').read_text()))==canonical(pg),'fix_hold graph changed'
 assert (OUT/'before_hold.sdc').read_bytes()==(OUT/'effective.sdc').read_bytes()
 timing=(OUT/'final.timing').read_text();setup=float(re.search(r'SWNS:\s*([-+\d.]+)ns',timing)[1]);hold=float(re.search(r'HWNS:\s*([-+\d.]+)ns',timing)[1])
 report={'board':BOARD,'setup_wns_ns':setup,'hold_wns_ns':hold,'native_mslice':sum(k=='EG_PHY_MSLICE' for k,p,s in pg.values()),'native_lslice':sum(k=='EG_PHY_LSLICE' for k,p,s in pg.values()),'native_guard_branches':len(branches),'pass':setup>=0 and hold>=0,'phase':'physical_pending_audit','hardware_accessed':False,'place_strategy':STRATEGY or 'default','place_seed':SEED}
 save('physical.json',report)
 print(json.dumps(report),flush=True)
 if not report['pass']:raise RuntimeError('Final timing gate failed')
 # Bit generation follows a separate explicit audit command; never automatic on slack alone.


