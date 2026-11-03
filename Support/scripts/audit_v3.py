from pathlib import Path
import json,re,sys,subprocess,hashlib
from scene_common import ROOT,CACHE,write_json
TD=r'D:\apps\anlogic\bin\td_commands_prompt.exe'
def run(out,name,lines):
 lines=[x for line in lines for x in ([line,'set_param flow thread 8'] if line.startswith('import_db ') else [line])]
 (out/(name+'.tcl')).write_text('\n'.join(lines)+f'\nputs {name.upper()}_DONE\n')
 with (out/(name+'.log')).open('w') as log:p=subprocess.run([TD],cwd=out,input='source '+name+'.tcl\nexit\n',text=True,stdout=log,stderr=subprocess.STDOUT)
 text=(out/(name+'.log')).read_text(errors='replace')
 if p.returncode or name.upper()+'_DONE' not in text or re.search(r'\b(ERROR|FATAL)\b',text):raise RuntimeError(text[-1500:])
def out_for(role):
 pointer=ROOT/f'reports/BUILD_{role.upper()}_ACTIVE.json'
 return Path(json.loads(pointer.read_text())['path']) if pointer.exists() else CACHE/('build_'+role)
def query(role):
 out=out_for(role)
 lines=['import_device eagle_s20.db -package EG4S20BG256','import_db routed.db','update_timing -mode final',
 'report_timing_ignored -ep_num 10000 -file ignored.timing','report_timing_exception -ep_num 10000 -file exceptions.timing','set ff [open stage_objects.txt w]']
 pairs=[('NET:link/receiver/data_meta[*]','link/receiver/data_sync[*]'),('NET:link/receiver/request_meta','link/receiver/request_sync'),('NET:link/receiver/valid_meta','link/receiver/valid_sync'),('NET:link/transmitter/meta','link/transmitter/sync')]
 prefix='media/video_diagnostic' if role=='a' else 'screen/snapshot'
 pairs += [(prefix+'/request_sync[0]',prefix+'/request_sync[1]'),(prefix+'/ack_sync[0]',prefix+'/ack_sync[1]')]
 if role=='a':pairs += [('media/memory/client0/rsp_sync1','media/memory/client0/rsp_sync2'),('media/memory/req0_s1','media/memory/req0_s2'),('media/mem_ready_meta','media/memory_ready'),('media/observer/observed_m','media/observer/observed_s')]
 if role=='a':pairs += [('media/audio_snapshot/request_sync[0]','media/audio_snapshot/request_sync[1]'),('media/audio_snapshot/ack_sync[0]','media/audio_snapshot/ack_sync[1]')]
 else:
  pairs += [('active_m','active_s'),('uf_m','uf_s'),('banks/guard/hb1','banks/guard/hb2'),('banks/commands/ack1','banks/commands/ack2'),('banks/commands/req1','banks/commands/req2'),
   ('analysis/pcm/ack1','analysis/pcm/ack2'),('analysis/pcm/req1','analysis/pcm/req2'),('analysis/ov1','analysis/ov2'),
   ('banks/fifo0/rg1[*]','banks/fifo0/rg2[*]'),('banks/fifo0/wg1[*]','banks/fifo0/wg2[*]'),
   ('banks/fifo1/rg1[*]','banks/fifo1/rg2[*]'),('banks/fifo1/wg1[*]','banks/fifo1/wg2[*]'),
   ('screen/audio_snapshot/request_sync[0]','screen/audio_snapshot/request_sync[1]'),('screen/audio_snapshot/ack_sync[0]','screen/audio_snapshot/ack_sync[1]'),
   ('replay_counter/snapshot/request_sync[0]','replay_counter/snapshot/request_sync[1]'),('replay_counter/snapshot/ack_sync[0]','replay_counter/snapshot/ack_sync[1]'),
   ('banks/playback_snapshot/request_sync[0]','banks/playback_snapshot/request_sync[1]'),('banks/playback_snapshot/ack_sync[0]','banks/playback_snapshot/ack_sync[1]')]
 if role=='a':
  for prefix in ['media/settings_snapshot','media/fx_configuration','media/fx_diagnostics','media/subtitle_snapshot','media/geometry_snapshot']:
   pairs += [(prefix+'/request_sync[0]',prefix+'/request_sync[1]'),(prefix+'/ack_sync[0]',prefix+'/ack_sync[1]')]
  pairs += [('media/fade/commit_sync1','media/fade/commit_sync2'),('media/fade/done_sync1','media/fade/done_sync2'),('media/fade/start_sync1','media/fade/start_sync2'),('media/picture_fx/brightness_m[*]','media/picture_fx/brightness_s[*]'),('media/picture_fx/contrast_m[*]','media/picture_fx/contrast_s[*]')]
 else:
  pairs += [('microphone/hb1','microphone/hb2'),('microphone/samples/ack1','microphone/samples/ack2'),('microphone/samples/req1','microphone/samples/req2')]
  for prefix in ['banks/volume_snapshot']:
   pairs += [(prefix+'/request_sync[0]',prefix+'/request_sync[1]'),(prefix+'/ack_sync[0]',prefix+'/ack_sync[1]')]
  pairs += [('banks/volume_commands/ack1','banks/volume_commands/ack2'),('banks/volume_commands/req1','banks/volume_commands/req2')]
  for prefix in ['microphone/diagnostics']:
   pairs += [(prefix+'/request_sync[0]',prefix+'/request_sync[1]'),(prefix+'/ack_sync[0]',prefix+'/ack_sync[1]')]
 if role=='a':
  pairs += [('media/layer_fault_diag/meta','media/layer_fault_diag/sync'),('media/safe_m1','media/safe_sys'),('media/layers/fault_m1','media/layers/fault_p'),
   ('media/layers/prefetch/epoch_m1','media/layers/prefetch/epoch_m2'),
   ('media/layers/prefetch/rb1[*]','media/layers/prefetch/rb2[*]'),
   ('media/layers/prefetch/rf1[*]','media/layers/prefetch/rf2[*]'),
   ('media/layers/prefetch/pb1[*]','media/layers/prefetch/pb2[*]'),
   ('media/layers/prefetch/pf1[*]','media/layers/prefetch/pf2[*]')]
  for prefix in ['media/layer_snapshot','media/layer_diag_snapshot']:
   pairs += [(prefix+'/request_sync[0]',prefix+'/request_sync[1]'),(prefix+'/ack_sync[0]',prefix+'/ack_sync[1]')]
 if role=='b':pairs += [('history_ready_meta','history_ready_sync')]
 if role=='b':pairs += [('recorder/play_commands/ack1','recorder/play_commands/ack2'),('recorder/play_commands/req1','recorder/play_commands/req2'),('recorder/stop_meta','recorder/stop_sync'),('banks/borrow_meta','banks/borrow_sync')]
 if role=='b':
  from scene_mapped_graph import graph
  g=graph((out/'routed.v').read_text());pads=[n.lstrip('\\') for n,(k,p,w) in g.items() if k=='EG_PHY_PAD' and w.get('ipad')=='ir_rx'];assert len(pads)==1
  pairs += [('PIN:'+pads[0]+'.diq[0]','ir_receiver/ir_sync')]
 write_json(out/'stage_pairs.json',pairs)
 for i,(a,b) in enumerate(pairs):
  source='get_nets -hier {'+a[4:]+'}' if a.startswith('NET:') else 'get_pins -hier {'+a[4:]+'}' if a.startswith('PIN:') else 'get_regs {'+a+'}'
  mode='-through' if a.startswith('NET:') else '-from'
  lines += [f'set aa [{source}]',f'set bb [get_regs {{{b}}}]',f'puts $ff [list STAGE {i} [llength $aa] [llength $bb]]',f'if {{[llength $aa] && [llength $bb]}} {{report_timing_path {mode} $aa -to $bb -ep_num 100 -file stage_{i}.timing}}']
 if role=='a':lines += ['set pp [get_nets -hier {media/memory/memory/u2_ram/SDRAM_CLK}]','report_property $pp','set pp [get_pins -of $pp]','puts $ff [list SDRAM_CLOCK $pp]']
 if role=='a':
  from scene_mapped_graph import graph,bits
  gg=graph((out/'routed.v').read_text())
  sinks=[n for n,(k,p,w) in gg.items() if k in ['EG_PHY_MSLICE','EG_PHY_LSLICE'] and '\\link/parser/crc_errors[13]' in bits(w.get('q',''))]
  assert len(sinks)==1,sinks
  pin=sinks[0].lstrip('\\')+'.sr'
  reset_net=gg[sinks[0]][2]['sr'].lstrip('\\')
  lines += ['report_timing_path -through [get_nets -hier {'+reset_net+'}] -to [get_pins -hier {'+pin+'}] -ep_num 20 -file reset_former_endpoint.timing']
 if role=='a':lines += ['report_timing_path -through [get_nets -hier {rst_n}] -ep_num 20 -file reset_paths.timing','report_timing_path -from [get_regs {controls/state[*] controls/panel_q}] -to [get_regs {controls/action_value[*] controls/hint[*]}] -ep_num 20 -file menu_paths.timing']
 lines+=['close $ff'];run(out,'audit_query',lines)
if __name__=='__main__':
 query(sys.argv[1])
