`timescale 1ns/1ps
`include "card_layout.vh"
`include "scene_protocol.vh"
`include "ui_protocol.vh"
`include "record_params.vh"
module scene_b_top(
 input wire sys_clk,sys_rst_n,uart_rx,ir_rx,output wire uart_tx,output wire [3:0] led,
 input wire [7:0] f_data,input wire f_clk,f_valid,output wire f_ready,
 output wire [7:0] r_data,output wire r_clk,r_valid,input wire r_ready,
 output wire HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,input wire key1,key2,key3,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso,audio_mclk,
 output wire audio_bclk,audio_lrck,audio_data,output wire mic_sck,mic_ws,input wire mic_sd,
 input wire sw1,sw2,sw3,sw4,output wire [7:0] seg_sel,seg_data
);
 wire rst_n;power_reset_seq startup(sys_clk,rst_n);
 reg [31:0] clock_count;
 always @(posedge sys_clk)if(!rst_n)clock_count<=0;else clock_count<=clock_count+1'b1;
 assign seg_sel=8'hff;assign seg_data=8'hff;
 wire [7:0] command,uart_command;wire command_valid,uart_command_valid;
 wire [3:0] short_key,long_key,switches;wire input_activity,input_blocked;
 wire ms_tick,all_keys_released,chord_blocked;wire [3:0] key_down;
 // Physical keys only at this conditioner
 b_inputs inputs(sys_clk,rst_n,{key3,key2,key1,sys_rst_n},{sw4,sw3,sw2,sw1},short_key,long_key,switches,input_activity,input_blocked,ms_tick,key_down,all_keys_released,chord_blocked);
 wire initialized,card_fault,sd_fault,sreq,saccepted,svalid,send,serror,sready;
 wire [31:0] lba,sd_wait;wire [32:0] capacity;wire [7:0] sd_byte,sd_code;wire [191:0] sd_diag;
 wire phy_request,phy_write,phy_accepted,phy_valid,phy_complete,phy_error,sd_idle;
 wire [31:0] phy_lba;wire [8:0] write_address;wire [7:0] write_data;
 wire rec_sector_req,rec_sector_write,rec_sector_ready,rec_sector_accepted,rec_sector_valid,rec_sector_complete,rec_sector_error;
 wire [31:0] rec_sector_lba;
 wire record_owner,record_preflight;wire [2:0] record_mode_state;
 reg [15:0] record_probe_generation;reg [14:0] record_probe_age;
 sd_owner sd_owner(sys_clk,rst_n,record_owner,sreq,lba,saccepted,svalid,send,serror,
  rec_sector_req,rec_sector_lba,rec_sector_write,rec_sector_ready,rec_sector_accepted,rec_sector_valid,rec_sector_complete,rec_sector_error,
  phy_request,phy_lba,phy_write,sready,phy_accepted,phy_valid,phy_complete,phy_error,sd_idle);
 scene_sd_sector sd(sys_clk,rst_n,sd_ncs,sd_dclk,sd_mosi,sd_miso,initialized,capacity,card_fault,
 phy_request,phy_lba,sready,phy_accepted,sd_byte,phy_valid,phy_complete,phy_error,sd_fault,sd_code,sd_wait,sd_diag,phy_write,write_data,write_address,);
 wire ui_scan_done,ui_save_committed,ui_slot_ready,record_saved;wire [4:0] ui_save_progress,record_remaining;
 wire ui_save_protected=ui_save_committed && record_state==4;
 reg catalog_start,started;wire opened,file_error;wire [7:0] file_code;wire [31:0] file_bytes;
 reg [3:0] current;
 (* ASYNC_REG="TRUE" *)reg active_m,active_s,uf_m,uf_s,sw_m,sw_s,right_m,right_s,wave_m,wave_s;
 wire byte_ready,byte_valid,byte_error;wire [7:0] byte_data;
 wire [63:0] descriptor;wire [13:0] valid_files,rejected_files;wire [3:0] wav_valid,wav_rejected;
 wire demand,available;wire [31:0] byte_offset;wire [3:0] byte_file;
 wire feed_fault,scheduler_fault;wire [1:0] pcm_fault,quiescent,feed;
 wire [12:0] count0,count1;wire bind_valid,bind_bank,bind_ready,bind_done,bind_error;wire [1:0] bind_scene;
 wire frame_valid,frame_bank,frame_ready;wire [31:0] frame_data,frames0,frames1,loops0,loops1;wire [63:0] lengths;
 wire [31:0] served0,served1,served2;wire active_bank;
 wire [3:0] boot_completed;
 catalog_progress boot_progress(valid_files|rejected_files,boot_completed);
 wire image_ready,image_send,image_fault,image_done;
 scene_wav_service #(.MAX_FILE_BYTES(2764854)) files(sys_clk,rst_n,catalog_start,capacity,image_done,
 sreq,lba,saccepted,sd_byte,svalid,send,serror,opened,file_error,file_code,valid_files,rejected_files,wav_valid,wav_rejected,
 active_s,feed,count0,count1,bind_valid,bind_bank,bind_scene,bind_ready,bind_done,bind_error,
 frame_valid,frame_bank,frame_data,frame_ready && !record_owner,pcm_fault,scheduler_fault,frames0,frames1,loops0,loops1,
 demand,available,byte_file,byte_offset,byte_ready,byte_valid,byte_error,byte_data,2'd0,,served0,served1,served2,quiescent,4'd0,descriptor,lengths,ui_scan_done);
 wire audio_rst_n,clock_alive,clock_fault,underflow,sent_valid;wire [31:0] sent_frame,clock_events,illegal_ops;
 wire [6:0] sent_tag;wire clear_valid,clear_bank,clear_ready,clear_done,cfg_valid,cfg_ready,cfg_done;
 wire [5:0] cfg;wire [31:0] cfg_frames;wire [1:0] cfg_scene;
 wire [159:0] playback;wire music_valid,audio_idle,policy_fault;wire [1:0] music_id;wire [3:0] audio_state;wire [31:0] commits;
 wire has_record,can_record,record_quiet,record_clipped;
 wire [3:0] record_state,record_command;wire [7:0] record_error;
 wire [31:0] record_bytes;wire [22:0] record_samples;
 record_meter record_meter(record_samples,record_remaining);
 wire record_command_valid,record_command_ready,can_play,replay_select,replay_valid,replay_take,replay_boundary,replay_begin;
 wire [31:0] replay_frame;
 wire record_memory_write;wire [13:0] record_memory_address,record_playback_address;
 wire [7:0] record_memory_data,record_memory_read,record_playback_read;
 reg current_valid,busy,fault;reg [2:0] packet_aux;
 reg page_begin,page_applied;wire user_pause;reg [3:0] desired_page;
 wire demo_prepare;reg pending_demo,offer_demo;reg [1:0] prep_state;reg [3:0] a_switches;
 wire demo_active,demo_paused,demo_snapshot,demo_restore,demo_page_request;wire [1:0] demo_interval;wire [3:0] demo_page_target;
 wire demo_fault=fault || card_fault || sd_fault || clock_fault;
 wire history_view;
 wire eco_sleep,eco_standby,eco_sys_rst_n,eco_audio_rst_n;
 wire voice_mute;wire effective_mute,request_mic,hold_plot,wave_page,select_right;
 wire control_request,replay,voice_arm,voice_cancel,clear_peak;wire [3:0] requested_page,hint;wire [31:0] control_generation;
 wire window_active,window_capture,window_open,window_changed,window_listen,window_blocked;wire [31:0] window_control;wire [2:0] window_ui;wire [1:0] window_last,window_prep;
 wire active_mic,source_wait,mic_valid,mic_alive,mic_warmed,mic_activity;wire [34:0] mic_payload;wire [31:0] mic_overflows,mic_events;
 wire [31:0] source_generation,source_discontinuities,source_clips,feature_drops,feature_sequence;
 wire feature_pending,feature_take;wire [7:0] feature_data;wire [5:0] feature_address;
 reg feedback_valid,feedback_ok,voice_action;reg [1:0] feedback_command;reg [31:0] feedback_control;
 wire page10=current_valid && current==9 && !busy;
 wire analysis_mic=record_owner ? 1'b1:request_mic || window_active;
 wire replay_observed,record_owned_mclk;
 wire analysis_music=music_valid;
 wire analysis_right=select_right;
 wire [1:0] analysis_song=music_id;
 wire analysis_pause=user_pause || request_mic || window_active;
 wire analysis_mute=effective_mute;
 wire play_pause=user_pause || request_mic || window_active;
 wire remote_play_pause=play_pause && !record_owner;
 reg control_pending,pending_replay,pending_voice;reg [3:0] pending_page;
 wire board_busy=busy || control_pending || !audio_idle || !current_valid || fault;
 reg voice_next_applied;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)voice_next_applied<=0;
  else if(window_ui==1)voice_next_applied<=0;
  else if(page_applied && voice_page)voice_next_applied<=1;
 end
 wire [3:0] routed_short,routed_long,volume_target,record_volume;wire [1:0] volume_mode;
 wire [7:0] volume_generation;wire [15:0] volume_steps;wire volume_activity,volume_rejected;
 wire [21:0] volume_status;wire [12:0] sent_volume;
 wire ir_frame,ir_repeat,ir_held,ir_key_valid,ir_learning,ir_enabled,ir_learn_reject;
 wire [7:0] ir_address,ir_code,ir_frames,ir_repeats,ir_errors,ir_map_address,ir_accepts,ir_drops;
 wire [4:0] ir_key,ir_learned;wire ir_volume_valid,ir_volume_up,ir_volume_refresh;
 ir_nec_rx ir_receiver(sys_clk,rst_n,ms_tick,ir_rx,ir_frame,ir_repeat,ir_address,ir_code,ir_held,ir_frames,ir_repeats,ir_errors);
 ir_c453f_keymap ir_keymap(sys_clk,rst_n,ir_frame,ir_address,ir_code,uart_command,uart_command_valid,
 ir_key_valid,ir_key,ir_learning,ir_enabled,ir_learned,ir_map_address,,ir_learn_reject);
 wire ir_physical_block=!all_keys_released || chord_blocked || input_activity || input_blocked || (|short_key) || (|long_key);
 assign command=uart_command;assign command_valid=uart_command_valid;
 assign ir_volume_valid=0;assign ir_volume_up=0;assign ir_volume_refresh=0;
 wire ir_event;wire [4:0] ir_event_id;wire [2:0] ir_event_flags;
 ir_events ir_events(sys_clk,rst_n,ms_tick,ir_frame,ir_repeat,ir_held,ir_key_valid,ir_key,ir_physical_block,ir_event,ir_event_id,ir_event_flags,ir_drops);
 assign ir_accepts=ir_frames-ir_drops;
 wire ui_online,ui_event,ui_send_ready,ui_result_valid;wire [7:0] ui_event_id,ui_event_flags,ui_result,ui_drops;
 wire [63:0] ui_event_body;wire [31:0] ui_last_action,ui_session;wire [351:0] ui_status;
 wire [7:0] ui_op=ui_event_body[55:48],ui_value=ui_event_body[47:40];
 reg [7:0] ui_reason,ui_last_result;reg ui_menu_block,ui_menu_seen,ui_wait_open;reg [15:0] ui_context_generation;
 wire ui_accept=ui_event && ui_reason==`UI_OK;
 wire ui_controls=ui_accept && ui_op!=`UI_CONTEXT;
 wire eco_eligible=current_valid && current==3 && music_valid && !board_busy && !record_owner &&
  !request_mic && !window_active && window_ui==0 && !voice_arm && !demo_active && volume_mode==0 && !switches[0];
 low_power_control low_power(sys_clk,rst_n,ui_online,eco_eligible && !control_request && !fault && !card_fault && !sd_fault && !clock_fault,
  ui_accept && ui_op==`UI_VIEW,ui_value[1:0],eco_sleep,eco_standby);
 reset_sync eco_sys_reset(sys_clk,rst_n && !eco_sleep,eco_sys_rst_n);
 reset_sync eco_audio_reset(audio_mclk,audio_rst_n && !eco_sleep,eco_audio_rst_n);
 wire demo_start_event=ui_accept && ui_op==`UI_DEMO && ui_value>=1 && ui_value<=4;
 demo_control demo_control(sys_clk,rst_n,ui_online,demo_fault,ui_accept && ui_op==`UI_DEMO,ui_value,current,demo_active,demo_paused,demo_interval,demo_snapshot,demo_restore,demo_page_request,demo_page_target);
 wire ui_start=ui_accept && ui_op==`UI_RECORD;
 wire ui_probe=ui_accept && ui_op==`UI_PROBE;
 wire ui_play=ui_accept && ui_op==`UI_PLAY;
 wire ui_stop=ui_accept && ui_op==`UI_STOP;
 // Pause demo timing as soon as OK is decoded, while the reliable command
 // is in flight. The guard expires if that key is lost or rejected.
 reg demo_key_guard;reg [9:0] demo_key_age;
 wire demo_ok_event=demo_active && ir_event && ir_event_flags[0] && ir_event_id==4;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin demo_key_guard<=0;demo_key_age<=0;end
  else if(!demo_active || !ui_online || demo_fault || (ui_accept && ui_op==`UI_DEMO && ui_value==5))begin demo_key_guard<=0;demo_key_age<=0;end
  else if(demo_ok_event)begin demo_key_guard<=1;demo_key_age<=0;end
  else if(demo_key_guard && ms_tick)begin
   if(demo_key_age==999)begin demo_key_guard<=0;demo_key_age<=0;end else demo_key_age<=demo_key_age+1'b1;
  end
 end
 wire ui_record_base=page10 && !window_active && !voice_arm && volume_mode==0 && !control_pending && !control_request && !fault &&
   audio_idle && sd_idle && sready && image_ready && (!xfer_valid || image_done) && !grant_valid && !demand && !available && !sreq && quiescent==2'b11;
 always @*begin
  ui_reason=`UI_OK;
  if(ui_event_id!=0 || ui_event_flags!=0 || ui_event_body[63:56]!=`UI_VERSION || ui_event_body[39:16]!=0 || ui_op>`UI_VIEW)ui_reason=`UI_BAD;
  else if((ui_op==`UI_VOLUME && ui_value>9) || (ui_op==`UI_PAGE && ui_value>9) ||
   ((ui_op==`UI_CONTEXT || ui_op==`UI_PAUSE || ui_op==`UI_MUTE || ui_op==`UI_HOLD || ui_op==`UI_MIC || ui_op==`UI_RIGHT || ui_op==`UI_WAVE) && ui_value>1) ||
   (ui_op==`UI_VIEW && ui_value>3) || (ui_op==`UI_RECORD && ui_value!=1) || (ui_op==`UI_DEMO && (ui_value==0 || ui_value>7)) ||
   ((ui_op==`UI_REPLAY || ui_op==`UI_ARM || ui_op==`UI_CANCEL || ui_op==`UI_CLEAR || ui_op==`UI_PLAY || ui_op==`UI_STOP || ui_op==`UI_PROBE) && ui_value!=0))ui_reason=`UI_BAD;
  else if(ui_op==`UI_CONTEXT)begin end
  else if(ir_physical_block || (command_valid && manual_command))ui_reason=`UI_BUSY;
  else if(fault || card_fault || sd_fault || clock_fault)ui_reason=`UI_FAULT;
  else if((ui_op==`UI_MUTE && switches[3]) || (ui_op==`UI_HOLD && switches[1]) || (ui_op==`UI_MIC && switches[2]) || ((ui_op==`UI_WAVE || ui_op==`UI_VIEW) && switches[0]))ui_reason=`UI_LOCK;
  else if(ui_op==`UI_VIEW)begin
   if(ui_value==3 && !eco_eligible)ui_reason=`UI_BUSY;
   else if(!opened || valid_files!=14'h3fff || wav_valid!=4'hf)ui_reason=`UI_WAIT;
   else if(!music_valid || current<3 || current>8 || request_mic || record_owner || board_busy || window_active || window_ui!=0 || volume_mode!=0 || voice_arm)ui_reason=`UI_BUSY;
  end
  else if(ui_op==`UI_VOLUME || ui_op==`UI_MUTE || ui_op==`UI_HOLD || ui_op==`UI_RIGHT || ui_op==`UI_WAVE || ui_op==`UI_CLEAR)begin end
  else if(!opened || valid_files!=14'h3fff || wav_valid!=4'hf)ui_reason=`UI_WAIT;
  else if(ui_save_protected && (ui_op==`UI_PAGE || ui_op==`UI_DEMO || ui_op==`UI_STOP || ui_op==`UI_RECORD || ui_op==`UI_PLAY))ui_reason=`UI_BUSY;
  else case(ui_op)
   `UI_PAUSE,`UI_REPLAY:if(!music_valid || request_mic || board_busy || record_owner)ui_reason=`UI_BUSY;
   `UI_PAGE:if(board_busy || window_active || record_owner)ui_reason=`UI_BUSY;
   `UI_DEMO:if(ui_value<=4 ? (demo_active || board_busy || window_active || record_owner):
    (!demo_active || ui_value>=6 && (board_busy || window_active || record_owner)))ui_reason=`UI_BUSY;
   `UI_MIC,`UI_ARM:if(record_owner || board_busy || window_active)ui_reason=`UI_BUSY;
   `UI_PROBE:if(record_owner || !ui_record_base || !mic_alive || !mic_warmed)ui_reason=`UI_BUSY;
   `UI_RECORD:if(!record_preflight || !can_record)ui_reason=`UI_BUSY;
   `UI_PLAY:if(record_owner ? (record_state!=6 && !can_play):!ui_record_base)ui_reason=`UI_BUSY;
   `UI_STOP:if(!record_owner)ui_reason=`UI_WAIT;
  endcase
 end
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin ui_menu_block<=1;ui_menu_seen<=0;ui_wait_open<=0;ui_context_generation<=0;ui_last_result<=0;end
  else begin
   if(!ui_online)begin ui_menu_block<=1;ui_menu_seen<=0;ui_wait_open<=0;end
   if(ui_accept && ui_op==`UI_CONTEXT)begin
    ui_menu_seen<=1;ui_context_generation<=ui_event_body[15:0];
    if(ui_value[0])begin ui_menu_block<=1;ui_wait_open<=0;end
    else if(!ui_wait_open)ui_menu_block<=0;
   end
   if(ui_event)ui_last_result<=ui_reason;
   if(ir_event && ir_event_flags[0] && ir_event_id==6 && !demo_active)begin ui_menu_block<=1;if(!menu_open)ui_wait_open<=1;end
  end
 end
 // Long press enters the same confirmation flow as IR
 wire physical_record_request=page10 && routed_long[1] && volume_mode==0 && !record_owner;
 reg physical_record_pending;
 wire physical_record_send=physical_record_pending && !ir_physical_block && ui_online;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)physical_record_pending<=0;
  else if(!ui_online || !page10 || fault)physical_record_pending<=0;
  else if(physical_record_send && ui_send_ready)physical_record_pending<=0;
  else if(physical_record_request)physical_record_pending<=1;
 end
 wire record_gesture=ui_start;
 wire play_gesture=(page10 && routed_short[1] && volume_mode==0) || ui_play;
 wire [3:0] control_short=record_owner ? (ui_save_protected ? 4'd0:(routed_short & 4'b0001)):page10 ? (routed_short & 4'b1101):routed_short;
 wire [3:0] control_long=record_owner ? (ui_save_protected ? 4'd0:(routed_long & 4'b0001)):page10 ? (routed_long & 4'b1101):routed_long;
 wire normal_command_valid=command_valid && !ui_save_protected && (!record_owner || ((command>="0" && command<="9") || command=="b" || command=="n" || command=="z" || command=="h" || command=="H"));
 volume_ui volume_ui(sys_clk,rst_n,ms_tick,key_down,all_keys_released,chord_blocked,short_key,long_key,
 music_valid,!board_busy,request_mic,window_active,fault,demo_prepare,command,command_valid,
 ir_volume_valid,ir_volume_up,
 routed_short,routed_long,volume_mode,volume_target,volume_generation,volume_steps,volume_activity,volume_rejected,ir_volume_refresh,ui_accept && ui_op==`UI_VOLUME,ui_value[3:0],demo_start_event,demo_restore && !demo_fault && ui_online);
 b_controls controls(sys_clk,rst_n,control_short,control_long,switches,command,normal_command_valid,current,music_valid,board_busy,window_active,
 voice_action && volume_mode==0 && !volume_activity && !record_owner,feedback_command,control_request,requested_page,replay,user_pause,select_right,voice_mute,voice_arm,voice_cancel,clear_peak,
 effective_mute,request_mic,hold_plot,wave_page,control_generation,hint,demo_prepare,volume_activity || record_gesture || play_gesture || ui_controls || ir_event || (ui_accept && ui_op==`UI_CONTEXT && ui_value[0] && !ui_menu_block),volume_rejected,ui_controls,ui_op,ui_value,demo_start_event,demo_restore && !demo_fault && ui_online,history_view);
 wire leave_record=(control_request && (requested_page!=9 || demo_prepare)) || (control_pending && (pending_page!=9 || pending_demo));
 wire record_eligible=page10 && !window_active && !voice_arm && volume_mode==0 && !control_pending && !control_request && !fault && audio_idle && sd_idle && sready &&
  (play_gesture || mic_alive && mic_warmed) && image_ready && (!xfer_valid || image_done) && !grant_valid && !demand && !available && !sreq && quiescent==2'b11;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin record_probe_generation<=0;record_probe_age<=0;end
  else begin
   if(ui_probe)record_probe_generation<=ui_event_body[15:0];
   if(!record_preflight)record_probe_age<=0;
   else if(ms_tick && record_probe_age<20000)record_probe_age<=record_probe_age+1'b1;
  end
 end
 record_mode recording_mode(sys_clk,rst_n,record_gesture,record_eligible,short_key[2] || ui_stop,leave_record,
  record_state,can_record,record_quiet && sd_idle && sready,record_owner,record_command_valid,record_command,record_command_ready,record_mode_state,play_gesture,can_play,ui_probe,ui_start,!ui_online || fault || record_probe_age>=20000,record_preflight,record_saved);
 record_engine recorder(.clk(sys_clk),.rst_n(rst_n),.enabled(record_owner),.media_fault(sd_fault || card_fault || clock_fault),
  .command_valid(record_command_valid),.command(record_command),.command_ready(record_command_ready),
  .mic_valid(mic_valid),.mic_data(mic_payload),.mic_alive(mic_alive),.mic_warmed(mic_warmed),
  .has_record(has_record),.can_record(can_record),.io_quiescent(record_quiet),.backend_state(record_state),.ui_save_progress(ui_save_progress),
  .error_code(record_error),.clipped(record_clipped),.pcm_bytes(record_bytes),.samples(record_samples),
  .sector_request(rec_sector_req),.sector_lba(rec_sector_lba),.sector_write(rec_sector_write),
  .sector_ready(rec_sector_ready),.sector_accepted(rec_sector_accepted),.sector_data(sd_byte),
  .sector_valid(rec_sector_valid),.sector_complete(rec_sector_complete),.sector_error(rec_sector_error),
  .write_address(write_address),.write_data(write_data),.card_sectors(capacity),
  .mclk(audio_mclk),.audio_rst_n(audio_rst_n),.can_play(can_play),.replay_select(replay_select),.replay_valid(replay_valid),
  .replay_frame(replay_frame),.replay_take(replay_take),.replay_boundary(replay_boundary),.replay_begin(replay_begin),
  .memory_write(record_memory_write),.memory_address(record_memory_address),.memory_data(record_memory_data),
  .memory_read(record_memory_read),.play_read(record_playback_read),.playback_address(record_playback_address),.ui_save_committed(ui_save_committed),.ui_slot_ready(ui_slot_ready),.ui_saved(record_saved));
 reg [1:0] record_result;
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)record_result<=0;
  else if(!page10)record_result<=0;
  else if(record_saved)record_result<=1;
  else if(record_owner && record_state==9)record_result<=2;
  else if(ui_probe || play_gesture)record_result<=0;
 end
 mic_input microphone(sys_clk,eco_sys_rst_n,audio_mclk,mic_sd,2'd1,mic_sck,mic_ws,mic_valid,mic_payload,mic_alive,mic_warmed,mic_overflows,mic_events,mic_activity);
 analysis_window #(.INTERNAL_PREP(1)) voice_window(sys_clk,rst_n,1'b0,voice_arm,voice_cancel,
 current_valid && !busy && !fault,fault,1'b0,1'b0,active_mic && mic_alive && mic_warmed && !source_wait,
 control_generation,feedback_valid,feedback_ok,feedback_control,feedback_command,,window_open,window_capture,,window_active,window_control,window_changed,window_ui,window_last,
 window_listen,window_blocked,window_prep);

 always @(posedge sys_clk or negedge rst_n)if(!rst_n)begin active_m<=0;active_s<=0;uf_m<=0;uf_s<=0;sw_m<=0;sw_s<=0;right_m<=0;right_s<=0;wave_m<=0;wave_s<=0;end
 else begin active_m<=active_bank;active_s<=active_m;uf_m<=underflow;uf_s<=uf_m;sw_m<=sw4;sw_s<=sw_m;right_m<=sw3;right_s<=right_m;wave_m<=sw2;wave_s<=wave_m;end
 wire audio_hard_fault=file_error || scheduler_fault || clock_fault || uf_s || (music_valid && pcm_fault[active_s]);
 wire page_open=opened || valid_files[0];
 page_audio policy(sys_clk,rst_n,page_open,audio_hard_fault,page_begin,desired_page,current,page_applied,play_pause,effective_mute,
 active_s,count0,count1,lengths,quiescent,pcm_fault,feed,clear_valid,clear_bank,clear_ready,clear_done,
 bind_valid,bind_bank,bind_scene,bind_ready,bind_done,bind_error,cfg_valid,cfg,cfg_ready,cfg_done,cfg_frames,cfg_scene,
 music_valid,music_id,audio_idle,policy_fault,commits,audio_state,1'b0);
 wire [66:0] progress_record;wire [31:0] progress_expected;
 wire [1:0] progress_state;wire [3:0] progress_seconds,progress_segments;
 wire commit_pulse;wire [31:0] consumed_frame;
 scene_audio_banks banks(sys_clk,rst_n,audio_mclk,page_open,1'b0,clear_valid,clear_bank,clear_ready,clear_done,
 frame_valid && frame_ready && !record_owner,frame_bank,frame_data,frame_ready,count0,count1,cfg_valid,cfg,cfg_ready,cfg_done,
 active_bank,audio_bclk,audio_lrck,audio_data,audio_rst_n,sent_valid,sent_frame,underflow,clock_alive,clock_fault,clock_events,illegal_ops,
 cfg_frames,playback,1'b0,cfg_scene,sent_tag,commit_pulse,consumed_frame,progress_record,progress_expected,volume_target,volume_generation,volume_status,sent_volume,
 replay_select,replay_valid,replay_frame,replay_take,replay_boundary,replay_begin,record_owner,record_memory_write,record_memory_address,record_memory_data,record_memory_read,record_playback_address,record_playback_read,record_owned_mclk);
 wire [255:0] progress_row;
 play_progress progress_view(sys_clk,rst_n,music_valid,music_id,busy || !audio_idle || fault,current_valid,playback[63:32],playback[31:0],progress_record,progress_expected,progress_state,progress_seconds,progress_segments,progress_row);
 wire history_ready_pixel;
 (* ASYNC_REG="TRUE" *)reg history_ready_meta,history_ready_sync;
 always @(posedge sys_clk or negedge rst_n)
  if(!rst_n)begin history_ready_meta<=0;history_ready_sync<=0;end
  else begin history_ready_meta<=history_ready_pixel;history_ready_sync<=history_ready_meta;end
 wire qualified_hold=hold_plot && history_ready_sync;
 wire [127:0] heights;wire [2:0] waveform;wire wave_read_clk;wire [6:0] wave_read_address,wave_read_data;wire [1:0] wave_locked_bank;wire analysis_valid;wire [31:0] analysis_window,analysis_windows,analysis_drops,analysis_errors;
 wire [1:0] analysis_music_id;wire [8:0] peak_bin;
 wire [31:0] voice_energy,voice_feature_control;wire voice_feature_invalid;
 wire [4:0] play_level,play_peak;wire play_clipped,play_level_valid;
 wire record_mic,record_right;wire [3:0] record_page;
 analysis analysis(sys_clk,eco_sys_rst_n,audio_mclk,eco_audio_rst_n,sent_valid,sent_frame,sent_tag,analysis_right,analysis_song,analysis_music,analysis_pause,
 analysis_mic,qualified_hold,clear_peak,current,mic_valid,mic_payload,mic_alive,mic_warmed,
 window_capture && window_listen && !window_changed,window_control,feature_pending,feature_take,feature_address,feature_data,
 feature_sequence,source_generation,feature_drops,active_mic,source_wait,source_discontinuities,source_clips,record_mic,record_right,record_page,
 heights,waveform,analysis_valid,analysis_window,analysis_music_id,analysis_windows,analysis_drops,analysis_errors,peak_bin,
 analysis_mute,play_level,play_peak,play_clipped,play_level_valid,voice_energy,voice_feature_control,voice_feature_invalid,sent_volume,record_volume,wave_read_clk,wave_read_address,wave_read_data,wave_locked_bank,record_owner,replay_observed,a_switches[3:2]);
 wire [31:0] replay_completed_frames;
 replay_count replay_counter(sys_clk,rst_n,audio_mclk,audio_rst_n,commit_pulse,
  sent_valid && sent_tag[4] && (!sent_tag[3] || record_owned_mclk) && !sent_tag[2] && !sent_tag[0],consumed_frame,replay_completed_frames);
 wire [1:0] replay_progress_state;wire [3:0] replay_progress_seconds,replay_progress_segments;
 wire replay_requested=record_owner && record_state==6;
 replay_progress replay_progress(sys_clk,rst_n,replay_requested,!record_bytes[13],replay_completed_frames,replay_progress_state,replay_progress_seconds,replay_progress_segments);
 reg feature_seen;reg [31:0] seen_feature_sequence;
 wire voice_feature_event=feature_pending && (!feature_seen || feature_sequence!=seen_feature_sequence);
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin feature_seen<=0;seen_feature_sequence<=0;end
  else if(feature_pending)begin feature_seen<=1;seen_feature_sequence<=feature_sequence;end
 end
 wire [3:0] voice_reason;wire [31:0] voice_session,voice_max_energy;
 wire [7:0] voice_good,voice_invalid_count;wire voice_clipped,voice_data_bad,voice_cancelled,voice_rejected;
 voice_status voice_status(sys_clk,rst_n,voice_arm,voice_cancel,window_capture,window_blocked,window_ui,
 control_generation,window_control,voice_feature_event,voice_feature_control,voice_energy,voice_feature_invalid,
 source_clips,feature_drops,source_discontinuities,feedback_valid,feedback_ok,
 voice_reason,voice_session,voice_max_energy,voice_good,voice_invalid_count,voice_clipped,voice_data_bad,voice_cancelled,voice_rejected);
 assign ui_status={`UI_VERSION,{clock_alive,fault,can_play,can_record,has_record,record_owner,music_valid,current_valid},{4'd0,current},{4'd0,target},{4'd0,volume_target},{4'd0,volume_status[13:10]},volume_generation,{eco_sleep,2'd0,music_valid,!audio_idle,effective_mute,voice_mute,user_pause},{4'd0,switches},{history_view,source_wait,window_listen,window_active,request_mic,hold_plot,wave_page,select_right},{4'd0,record_state},record_error,{2'd0,valid_files[13:8]},valid_files[7:0],{busy || control_pending,(|rejected_files) || (|wav_rejected),opened,ui_scan_done,wav_valid},ui_last_result,ui_last_action[31:24],ui_last_action[23:16],ui_last_action[15:8],ui_last_action[7:0],8'h11,8'h10,8'hb0,8'h01,control_generation[31:24],control_generation[23:16],control_generation[15:8],control_generation[7:0],record_probe_generation[15:8],{6'd0,demo_paused,demo_active},ui_context_generation[15:8],ui_context_generation[7:0],record_bytes[31:24],record_bytes[23:16],record_bytes[15:8],record_bytes[7:0],{record_result,1'b0,record_state==3 ? record_remaining:ui_save_progress},{1'b0,record_samples[22:16]},record_samples[15:8],record_samples[7:0],{7'd0,volume_status[9]},volume_status[8:1],{4'd0,record_owner,ui_save_protected,ui_slot_ready,record_owner},record_probe_generation[7:0]};
 reg [31:0] ui_uptime;always @(posedge sys_clk or negedge rst_n)if(!rst_n)ui_uptime<=0;else if(ms_tick)ui_uptime<=ui_uptime+1'b1;
 wire ui_txvalid,ui_txready,ui_txdone,ui_rxready;wire [7:0] ui_txtype,ui_txid,ui_txflags,ui_txdata;wire [31:0] ui_txepoch,ui_txoffset;wire [9:0] ui_txlength;wire [8:0] ui_rxaddr;
 wire ui_packet=rxtype>=`UI_KEY && rxtype<=`UI_SYNC;
 wire txready,txdone,rxvalid;wire [7:0] rxtype,rxid,rxflags,rxdata;wire [31:0] rxepoch,rxoffset;wire [9:0] rxlength;
 wire [8:0] txaddr;wire [31:0] packets,crc_errors,format_errors,packet_timeouts,tx_timeouts;
 ui_link #(.HOST(0)) ui_link(.clk(sys_clk),.rst_n(rst_n),.ms_tick(ms_tick),.uptime(ui_uptime),
 .rx_valid(rxvalid && ui_packet),.rx_type(rxtype),.rx_id(rxid),.rx_flags(rxflags),.rx_epoch(rxepoch),.rx_offset(rxoffset),.rx_length(rxlength),.rx_ready(ui_rxready),.rx_addr(ui_rxaddr),.rx_data(rxdata),
 .tx_valid(ui_txvalid),.tx_ready(ui_txready),.tx_done(ui_txdone),.tx_type(ui_txtype),.tx_id(ui_txid),.tx_flags(ui_txflags),.tx_epoch(ui_txepoch),.tx_offset(ui_txoffset),.tx_length(ui_txlength),.tx_addr(txaddr),.tx_data(ui_txdata),
 .send_valid(physical_record_send || ir_event && !ir_physical_block),.send_ready(ui_send_ready),.send_id(physical_record_send ? 8'd20:{3'd0,ir_event_id}),.send_flags(physical_record_send ? 8'd1:{5'd0,ir_event_flags}),.send_body(64'd0),
 .event_valid(ui_event),.event_ready(1'b1),.event_result(ui_reason),.event_id(ui_event_id),.event_flags(ui_event_flags),.event_body(ui_event_body),
 .status_in(ui_status),.status_out(),.status_valid(),.online(ui_online),.result(ui_result),.result_valid(ui_result_valid),.last_action(ui_last_action),.drops(ui_drops),.session_out(ui_session));
 reg begin_file,message;reg [3:0] target;
 reg [31:0] epoch,applied,failures,timer;reg offer_pending,offering,packet_active,packet_offer;
 reg [31:0] xfer_epoch,xfer_size,msg_epoch,msg_offset;reg [7:0] msg_type,msg_file;reg [3:0] xfer_file;reg xfer_valid;
 reg pref_valid,pref_acked,pref_pending,pref_second,pref_reverse;reg [3:0] pref_file;reg [31:0] pref_epoch,pref_timer;
 wire prefetch_idle=opened && !record_owner && current_valid && !busy && audio_idle && !fault && !window_active && !request_mic && image_ready && (!xfer_valid || image_done) && !grant_valid;
 wire [3:0] first_pref=pref_reverse ? (current==0 ? 4'd9:current-1'b1):(current==9 ? 4'd0:current+1'b1);
 wire [3:0] second_pref=pref_reverse ? (pref_file==0 ? 4'd9:pref_file-1'b1):(pref_file==9 ? 4'd0:pref_file+1'b1);
 // Page changes do not revoke a grant already sent to A. Leave it intact
 // until A reports a cache hit (E3), requests TX, or the old epoch drains.
 // Drain for 1s: A can still retry the first request at 100ms, so replacing
 // the grant immediately would turn that valid request into a stale one.
 reg grant_valid;reg [3:0] grant_file;reg [31:0] grant_epoch;reg [25:0] grant_age;
 reg auto_enable,menu_open,status_pending;reg [25:0] auto_age;reg [7:0] last_auto_flags;
 wire auto_running,auto_request;wire [3:0] auto_target;wire [29:0] auto_elapsed;
 // Demo paging may run under MIC/HOLD, like UI_PAGE. Ordinary AUTO still
 // waits for those inhibits to clear.
 wire auto_eligible=!record_owner && (volume_mode==0) && !(|key_down) && !menu_open && !ui_menu_block && ui_online && !(ir_event && ir_event_flags[0]) && !(rxvalid && rxtype==8'he7 && rxflags[1]) && current_valid && opened && audio_idle && !board_busy && (!user_pause || demo_active) && (!request_mic || demo_active) && (!hold_plot || demo_active) && !window_active && !voice_arm && !fault;
 wire manual_command=command_valid && ((command>="0" && command<="9") || command=="b" || command=="n" || command=="p" || command=="v" || command=="z" || command=="r" || command=="c" || command=="x" || command=="m" || command=="j" || command=="h" || command=="H");
 wire manual_event=ui_controls || ir_event || volume_activity || (|key_down) || input_activity || (|short_key) || (|long_key) || control_request || replay || voice_action || voice_arm || voice_cancel || manual_command;
 autoflow autoflow(sys_clk,rst_n,auto_enable,auto_eligible,manual_event,current,control_generation,epoch,auto_request,auto_target,auto_running,auto_elapsed,demo_active,demo_paused || demo_key_guard || demo_ok_event,demo_page_request || (demo_active && ui_accept && ui_op==`UI_PAGE),demo_interval);
 wire [7:0] auto_flags={menu_open,fault,board_busy,window_active,request_mic,hold_plot || user_pause,auto_running,auto_enable};
 wire [3:0] auto_seconds,auto_reason;
 auto_status_pipe auto_view(sys_clk,rst_n,auto_enable,auto_running,auto_elapsed,fault,menu_open,
  window_active || voice_arm,request_mic,user_pause,hold_plot,board_busy || !audio_idle,
  current_valid && opened,auto_seconds,auto_reason,volume_mode!=0);
 wire image_message=rxvalid && (rxtype==`SCENE_IMAGE_REQ || rxtype==`SCENE_IMAGE_ACK || rxtype==`SCENE_IMAGE_RETRY);
 wire normal_request=busy && rxepoch==epoch && rxid=={4'd0,target};
 wire prefetch_request=grant_valid && rxepoch==grant_epoch && rxid=={4'd0,grant_file};
 reg [7:0] last_error;reg [1:0] restart_request;
 wire [31:0] image_epoch,image_offset,image_crc,image_next,retries,stales,rejections,bytes_read;
 // No fresh prefetch during the old grant drain: an epoch change clears
 // pref_pending, while grant_valid keeps prefetch_idle low.
 wire grant_draining=grant_valid && grant_epoch!=epoch && image_ready && (!xfer_valid || image_done);
 wire [7:0] image_file,image_flags,image_payload;wire [9:0] image_length;
 wire [31:0] page_bytes=`CARD_SIZES >> (target*32);
 wire aux_window,aux_feature,aux_pref,aux_status;wire aux_ui;reg ui_turn;
 scene_image_tx image(sys_clk,rst_n,begin_file,xfer_epoch,xfer_size,{4'd0,xfer_file},valid_files[xfer_file],image_ready,
 message,msg_type,msg_file,msg_epoch,msg_offset,demand,available,byte_offset,byte_file,
 available && byte_ready,byte_valid,byte_error,byte_data,image_send,txready && !offering && !packet_active && !aux_window && !aux_feature && !aux_pref && !aux_status && !aux_ui && !offer_pending,
 txdone && packet_active && !packet_offer && packet_aux==0,image_epoch,image_offset,image_file,image_flags,image_length,
 txaddr,image_payload,image_done,image_fault,image_crc,image_next,retries,stales,rejections,bytes_read);
 reg [1:0] previous_audio_control;reg [22:0] aux_timer;reg aux_pending;reg result_handled;reg voice_page;
 // Reserve the next slot for offer_pending. An aux packet starting on the
 // promotion edge would clear offering later in this always block and lose
 // the retry without ever sending the offer.
 assign aux_ui=ui_txvalid && !offer_pending && !offering && (!image_send || ui_turn);
 assign ui_txready=txready && !packet_active && aux_ui;assign ui_txdone=txdone && packet_active && packet_aux==5;
 assign aux_window=!aux_ui && aux_pending && !offer_pending && !offering && !image_send;
 assign aux_feature=!aux_ui && !aux_window && feature_pending && window_capture && !offer_pending && !offering && !image_send;
 assign aux_pref=!aux_ui && !aux_window && !aux_feature && pref_pending && !offer_pending && !offering && !image_send;
 assign aux_status=!aux_ui && !aux_window && !aux_feature && !aux_pref && status_pending && !offer_pending && !offering && !image_send;
 wire txvalid=!packet_active && (offering || (image_send && !offer_pending && !aux_ui) || aux_ui || aux_window || aux_feature || aux_pref || aux_status);
 assign feature_take=txdone && packet_active && packet_aux==2;
 assign feature_address=txaddr[5:0];
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin ui_turn<=1;previous_audio_control<=3;aux_timer<=0;aux_pending<=0;packet_aux<=0;feedback_valid<=0;feedback_ok<=0;feedback_command<=0;feedback_control<=0;voice_action<=0;result_handled<=0;end
  else begin
   feedback_valid<=0;voice_action<=0;previous_audio_control<={remote_play_pause,effective_mute};
   if(previous_audio_control!={remote_play_pause,effective_mute})aux_pending<=1;
   if(!window_active)result_handled<=0;
   if(aux_timer==4999999)begin aux_timer<=0;aux_pending<=1;end else aux_timer<=aux_timer+1'b1;
   if(window_changed)aux_pending<=1;
   if(txvalid && txready)begin
    ui_turn<=!aux_ui;packet_aux<=aux_ui ? 5:aux_window ? 1:aux_feature ? 2:aux_pref ? 3:aux_status ? 4:0;
    if(aux_window)aux_pending<=0;
   end
   if(rxvalid && rxtype==8'hea && rxepoch==epoch && rxoffset==window_control && window_active && window_capture && !voice_cancel && control_generation==window_control && !result_handled)begin
    feedback_valid<=1;feedback_ok<=rxflags[2];feedback_command<=rxflags[1:0];feedback_control<=rxoffset;result_handled<=1;
    if(rxflags[2])voice_action<=1;
   end
  end
 end
 scene_link link(sys_clk,rst_n,f_data,f_clk,f_valid,f_ready,r_data,r_clk,r_valid,r_ready,
 txvalid,txready,txdone,aux_ui ? ui_txtype:offering ? 8'he0 : aux_window ? 8'he8:aux_feature ? 8'he9:aux_pref ? 8'he1:aux_status ? 8'he6:`SCENE_IMAGE_DATA,
 aux_ui ? ui_txid:offering ? {4'd0,target}:aux_pref ? {4'd0,pref_file}:aux_window || aux_feature || aux_status ? 8'd0:image_file,
 aux_ui ? ui_txflags:offering ? {voice_page,offer_demo,6'd0}:aux_window ? {3'd0,remote_play_pause,effective_mute,mic_alive && mic_warmed && active_mic,window_capture,window_active}:aux_pref ? {7'd0,pref_reverse}:aux_feature ? 8'd0:aux_status ? auto_flags:image_flags,
 aux_ui ? ui_txepoch:offering || aux_window || aux_feature || aux_status ? epoch:aux_pref ? pref_epoch:image_epoch,aux_ui ? ui_txoffset:offering ? page_bytes:aux_window ? window_control:aux_feature ? feature_sequence:aux_pref ? (`CARD_SIZES >> (pref_file*32)):image_offset,
 aux_ui ? ui_txlength:offering || aux_window || aux_pref || aux_status ? 10'd0:aux_feature ? 10'd36:image_length,txaddr,packet_aux==5 ? ui_txdata:packet_aux==2 ? feature_data:image_payload,rxvalid,ui_packet ? ui_rxready:1'b1,rxtype,rxid,rxflags,rxepoch,rxoffset,rxlength,
 ui_packet ? ui_rxaddr:9'd0,rxdata,packets,crc_errors,format_errors,packet_timeouts,tx_timeouts);
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin catalog_start<=0;started<=0;begin_file<=0;message<=0;target<=0;current<=0;current_valid<=0;
   busy<=0;fault<=0;epoch<=0;applied<=0;failures<=0;timer<=0;offer_pending<=0;offering<=0;packet_active<=0;packet_offer<=0;last_error<=0;restart_request<=0;page_begin<=0;page_applied<=0;desired_page<=0;voice_page<=0;control_pending<=0;pending_replay<=0;pending_voice<=0;pending_page<=0;
   xfer_epoch<=0;xfer_size<=0;xfer_file<=0;xfer_valid<=0;msg_epoch<=0;msg_offset<=0;msg_type<=0;msg_file<=0;
   pref_valid<=0;pref_acked<=0;pref_pending<=0;pref_second<=0;pref_reverse<=0;pref_file<=0;pref_epoch<=0;pref_timer<=0;grant_valid<=0;grant_file<=0;grant_epoch<=0;grant_age<=0;auto_enable<=0;menu_open<=0;auto_age<=50000000;pending_demo<=0;offer_demo<=0;prep_state<=0;a_switches<=0;status_pending<=1;last_auto_flags<=0;end
  else begin
   catalog_start<=0;begin_file<=0;message<=0;page_begin<=0;page_applied<=0;
   last_auto_flags<=auto_flags;
   if(last_auto_flags!=auto_flags || aux_timer==4999999)status_pending<=1;
   if(txvalid && txready && aux_status)status_pending<=0;
   if(txvalid && txready && aux_pref)pref_pending<=0;
   if(txvalid && txready && aux_pref)begin grant_valid<=1;grant_file<=pref_file;grant_epoch<=pref_epoch;end
   else if(grant_draining && grant_age==49999999)grant_valid<=0;
   // Keep grant_age reset off the long packet-arbitration fanout.
   // A new grant already gets zero here because !grant_draining.
   if(grant_draining && grant_age!=49999999)grant_age<=grant_age+1'b1;else grant_age<=0;
   if(rxvalid && rxtype==8'he3 && grant_valid && rxepoch==grant_epoch && rxid=={4'd0,grant_file})grant_valid<=0;
   if(auto_age<50000000)auto_age<=auto_age+1'b1;else begin auto_enable<=0;menu_open<=0;end
   if(rxvalid && rxtype==8'he7)begin auto_enable<=rxflags[0];menu_open<=rxflags[1];a_switches<=rxflags[5:2];auto_age<=0;status_pending<=1;end
   if(pref_timer==24999999)begin pref_timer<=0;if(pref_valid && !pref_acked && !busy && pref_epoch==epoch)pref_pending<=1;end else pref_timer<=pref_timer+1'b1;
   if(prefetch_idle && !pref_valid)begin
    pref_valid<=1;pref_acked<=0;pref_second<=0;pref_file<=first_pref;pref_epoch<=epoch;pref_pending<=1;pref_timer<=0;
   end else if(prefetch_idle && pref_valid && pref_acked && !pref_second && pref_epoch==epoch)begin
    pref_acked<=0;pref_second<=1;pref_file<=second_pref;pref_pending<=1;pref_timer<=0;
   end
   if(rxvalid && rxtype==8'he3 && pref_valid && rxepoch==pref_epoch && rxid=={4'd0,pref_file})begin pref_acked<=1;pref_pending<=0;end
   if(image_message && restart_request==0 && !begin_file)begin
    if(rxtype==`SCENE_IMAGE_REQ && rxoffset==0 && image_ready && (!xfer_valid || image_done || image_fault) && (normal_request || prefetch_request))begin
     xfer_epoch<=rxepoch;xfer_file<=rxid[3:0];xfer_size<=`CARD_SIZES >> (rxid[3:0]*32);xfer_valid<=1;begin_file<=1;restart_request<=2;
     if(prefetch_request)grant_valid<=0;
     msg_type<=rxtype;msg_file<=rxid;msg_epoch<=rxepoch;msg_offset<=rxoffset;
    end else if(xfer_valid && rxepoch==xfer_epoch && rxid=={4'd0,xfer_file})begin
     message<=1;msg_type<=rxtype;msg_file<=rxid;msg_epoch<=rxepoch;msg_offset<=rxoffset;
    end
   end
   if(restart_request!=0)begin restart_request<=restart_request-1'b1;if(restart_request==1)message<=1;end
   if(initialized && !started)begin started<=1;catalog_start<=1;end
   if(page_open && audio_idle && !busy && !current_valid && !fault )begin
    epoch<=clock_count;target<=0;desired_page<=0;page_begin<=1;busy<=1;offer_pending<=1;timer<=0;
   end
   if(!control_pending && !control_request && !voice_action)pending_voice<=0;
   if(voice_action && feedback_command==1)pending_voice<=1;
   if(auto_request && (auto_enable || demo_active) && auto_eligible && !manual_event && !control_pending)begin control_pending<=1;pending_page<=auto_target;pending_replay<=0;pending_voice<=0;end
   if((|short_key) || (|long_key) || manual_command || voice_arm || replay)prep_state<=0;
   if((control_request || replay) && !(page10 && requested_page==9 && !demo_prepare))begin control_pending<=1;pending_page<=requested_page;pending_replay<=replay;pending_demo<=demo_prepare;end
   if(demo_page_request)begin control_pending<=1;pending_page<=demo_page_target;pending_replay<=0;pending_demo<=0;pending_voice<=0;end
   if(ui_save_protected && control_pending)begin control_pending<=0;pending_demo<=0;pending_voice<=0;pending_replay<=0;end
   if(demo_prepare)begin prep_state<=1;pending_voice<=0;end
   if(control_pending && !control_request && !replay)begin
    if(!record_owner && opened && audio_idle && !busy && valid_files==14'h3fff && wav_valid==4'hf)begin
     target<=pending_replay ? current:pending_page;
     desired_page<=pending_replay ? current:pending_page;page_begin<=1;epoch<=epoch+1'b1;
     voice_page<=pending_voice && !pending_demo;offer_demo<=pending_demo;pending_demo<=0;pending_voice<=0;control_pending<=0;
     busy<=1;fault<=0;last_error<=0;offer_pending<=1;timer<=0;pref_valid<=0;pref_pending<=0;pref_second<=0;
     if(!pending_replay)pref_reverse<=!pending_demo && pending_page<current && !(current==9 && pending_page==0 && auto_enable);
    end
   end
   if(timer>=(busy ? 499999:49999999))begin timer<=0;if(page_open && !fault)offer_pending<=1;end
   else timer<=timer+1'b1;
   if(offer_pending && !packet_active && !offering)begin offering<=1;offer_pending<=0;end
   if(txvalid && txready)begin packet_active<=1;packet_offer<=offering;offering<=0;end
   if(txdone && packet_active)packet_active<=0;
   if(rxvalid && rxepoch==epoch && rxid=={4'd0,target})begin
    if(rxtype==8'he2)begin if(busy && offer_demo)prep_state<=2;if(busy)page_applied<=1;current<=target;current_valid<=1;busy<=0;fault<=0;if(busy)applied<=applied+1'b1;end
    if(rxtype==8'he4)begin busy<=0;fault<=1;last_error<=rxflags;failures<=failures+1'b1;end
   end
   if(file_error || card_fault || sd_fault || audio_hard_fault || policy_fault)begin fault<=1;last_error<=file_error ? file_code:sd_code;end
  end
 end
 reg [3:0] led_q;
 always @(posedge sys_clk)if(!rst_n)led_q<=0;else led_q<={fault,busy,current_valid,clock_count[25]};
 wire [512:0] native_donors;assign native_donors[0]=led_q[0];genvar nd;
 generate for(nd=0;nd<512;nd=nd+1)begin:g_native_hold
  (* keep="true" *) AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(native_donors[nd]),.o(native_donors[nd+1]));
 end endgenerate
 assign led={led_q[3:1],native_donors[512]};
 wire [7:0] query;
 wire [31:0] state_word={last_error,12'd0,opened,fault,busy,current_valid,target,current};
 wire [31:0] audio_status={11'd0,sw_s,music_id,music_valid,play_pause,effective_mute,clock_alive,uf_s,clock_fault,policy_fault,audio_idle,audio_state,6'd0};
 wire [1:0] prep_view=prep_state==2 && (busy || control_pending || !audio_idle || window_active || menu_open) ? 2'd1:prep_state;
 wire [127:0] release_q={epoch,state_word,crc_errors,analysis_errors};
 wire [127:0] release_i={{4'd0,rejected_files,valid_files},bytes_read,retries,rejections};
 wire [127:0] release_p={audio_status,playback[95:0]};
 wire [127:0] release_y={{15'd0,record_owner,record_error,record_state,record_clipped,record_mode_state==4,can_record,has_record},record_bytes,rec_sector_lba,{29'd0,record_mode_state}};
 wire [127:0] stats;
 debug_select #(.LAST_QUERY("Y")) debug_select(sys_clk,rst_n,uart_command,uart_command_valid,release_q,release_i,release_p,release_y,query,stats);
 scene_uart #(.BOARD(8'h42),.DIV(109)) diagnostics(sys_clk,rst_n,uart_rx,uart_tx,stats,query,uart_command,uart_command_valid);
 status_screen screen(sys_clk,rst_n,{fault,busy,current_valid,opened},current,target,last_error,
 HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 analysis_music || replay_observed,analysis_song,analysis_pause && !replay_observed,analysis_mute,audio_idle,analysis_right,wave_page,analysis_valid,analysis_music_id,heights,waveform,analysis_window,
 hold_plot,analysis_mic && !replay_observed,record_mic,record_right,record_page,window_ui,mic_alive,mic_warmed,source_wait,hint,switches,voice_mute,user_pause,window_active,window_blocked,window_last,auto_flags,voice_next_applied,
 play_level,play_peak,play_clipped,play_level_valid,auto_seconds,auto_reason,prep_view,{a_switches,switches},record_owner ? (record_state==1 && has_record && record_samples==`BASIC_FRAMES ? 4'd10:record_state):(record_result==1 ? 4'd10:record_result==2 ? 4'd9:voice_reason),
 replay_requested ? replay_progress_state:progress_state,
 record_owner && (record_state==3 || record_state==4) ? (record_state==3 ? record_remaining[4:1]:ui_save_progress[4:1]):(replay_requested ? replay_progress_seconds:progress_seconds),
 record_owner && (record_state==3 || record_state==4) ? {record_state==3 ? record_remaining[0]:ui_save_progress[0],3'd0}:(replay_requested ? replay_progress_segments:progress_segments),
 volume_mode,volume_target,record_volume,volume_status,volume_generation,boot_completed,started,wave_read_clk,wave_read_address,wave_read_data,wave_locked_bank,record_owner,record_result!=0,history_ready_pixel,history_view,eco_sleep,eco_standby);
endmodule
