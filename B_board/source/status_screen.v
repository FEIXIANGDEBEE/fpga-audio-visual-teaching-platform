`timescale 1ns/1ps

module status_screen(input wire clk,rst_n,input wire [3:0] status,input wire [3:0] page,target,input wire [7:0] error,
 output wire HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 input wire music_valid,input wire [1:0] music_id,input wire pause,mute,audio_idle,right,wave_page,
 input wire analysis_valid,input wire [1:0] analysis_music,input wire [127:0] heights,input wire [2:0] waveform,input wire [31:0] analysis_window,
 input wire hold_plot,request_mic,record_mic,record_right,input wire [3:0] record_page,input wire [2:0] voice_ui,
 input wire mic_alive,mic_warmed,source_wait,input wire [3:0] hint,switches,input wire voice_mute,user_pause,window_active,window_blocked,input wire [1:0] last_command,input wire [7:0] auto_flags,input wire next_applied,
 input wire [4:0] play_level,play_peak,input wire play_clipped,play_level_valid,input wire [3:0] auto_seconds,auto_reason,input wire [1:0] prep_state,input wire [7:0] prep_switches,input wire [3:0] voice_reason,input wire [1:0] progress_state,input wire [3:0] progress_seconds,progress_segments,input wire [1:0] volume_mode,input wire [3:0] volume_target,record_volume,input wire [21:0] volume_status,input wire [7:0] volume_generation,input wire [3:0] boot_completed,input wire boot_check,output wire wave_read_clk,output wire [6:0] wave_read_address,input wire [6:0] wave_read_data,output wire [1:0] wave_locked_bank,input wire record_mode,record_result_valid,output wire history_ready,input wire history_view,input wire eco_sleep,eco_standby);
 wire pclk,sclk,locked,prst,screen_rst_n;
 video_pll pll(clk,!rst_n || eco_sleep,sclk,pclk,locked,eco_standby);
 reset_sync source_reset(clk,rst_n && !eco_sleep && !eco_standby && locked,screen_rst_n);
 reset_sync reset(pclk,rst_n && !eco_sleep && !eco_standby && locked,prst);
 wire hs,vs,de,blank_tick,frame_tick;wire [9:0] x,y;
 video_timing_640x480 timing(pclk,prst,hs,vs,de,x,y,blank_tick,frame_tick);
 wire [136:0] ui;
 cdc_snapshot #(.WIDTH(137)) snapshot(clk,screen_rst_n,{boot_check,boot_completed,volume_mode,volume_target,record_volume,volume_status,volume_generation,progress_state,progress_seconds,progress_segments,voice_reason,prep_state,prep_switches,auto_reason,auto_seconds,auto_flags,last_command,user_pause,voice_mute,window_active,window_blocked,history_view,next_applied,switches,hold_plot,request_mic,record_mic,record_right,record_page,voice_ui,mic_alive,mic_warmed,source_wait,hint,record_result_valid,record_mode,status,page,target,error},pclk,prst,blank_tick,ui);
 wire [662:0] plot;wire [162:0] compact_plot;wire [4:0] wave_index;
 wire [662:0] raw_plot={compact_plot[153:3],512'd0};
 wire [127:0] display_heights,peak_heights;
 wire effective_hold=ui[39] && history_ready;
 spectrum_motion spectrum_motion(pclk,prst,frame_tick,raw_plot[642],1'b0,effective_hold,
  {compact_plot[136:135],compact_plot[140:139],compact_plot[132:131]},ui[15:12],compact_plot[130:3],display_heights,peak_heights);
 // Plot state occupies reserved low bits of the existing snapshot.
 wire [3:0] peak_band;
 display_peak display_peak(pclk,prst,frame_tick,raw_plot[642],1'b0,effective_hold,
  {compact_plot[136:135],compact_plot[140:139],compact_plot[132:131]},ui[15:12],compact_plot[130:3],peak_band);
 wire [5:0] target_identity={ui[15:12],ui[38],compact_plot[162]};
 wire [5:0] data_identity={compact_plot[140:139],compact_plot[132:131],compact_plot[136],compact_plot[135]};
 reg [5:0] previous_target;reg [7:0] previous_window;reg [4:0] quiet_frames;
 reg identity_changed,identity_stable;wire paused=ui[49] || compact_plot[138];
 wire fresh=compact_plot[161:154]!=previous_window;
 wire stale=quiet_frames>=24;
 always @(posedge pclk or negedge prst)
  if(!prst)begin previous_target<=0;previous_window<=0;quiet_frames<=24;identity_changed<=1;identity_stable<=0;end
  else if(frame_tick)begin
   previous_target<=target_identity;previous_window<=compact_plot[161:154];
   identity_changed<=target_identity!=previous_target;
   identity_stable<=target_identity==previous_target && target_identity==data_identity;
   if(target_identity!=previous_target)quiet_frames<=24;
   else if(fresh && raw_plot[642])quiet_frames<=0;
   else if(quiet_frames<24)quiet_frames<=quiet_frames+1'b1;
  end
 assign plot={raw_plot[662:640],display_heights,374'd0,paused,stale,identity_stable,identity_changed,fresh,effective_hold,peak_band,peak_heights};
 assign wave_read_clk=pclk;assign wave_read_address={compact_plot[1:0],wave_index};
 // Six metadata bits carry the held page/MIC/channel identity.
 // The bundled snapshot remains 163 bits wide.
 plot_snapshot audio_snapshot(clk,screen_rst_n,{right,analysis_window[7:0],play_level_valid,play_clipped,play_peak,play_level,music_valid,record_page[3:2],pause,mute,record_mic,record_right,wave_page,analysis_valid,record_page[1:0],heights,waveform},pclk,prst,blank_tick,compact_plot,wave_locked_bank);
 wire [136:0] record_ui={ui[136:38],compact_plot[136],compact_plot[135],compact_plot[140:139],compact_plot[132:131],ui[31:0]};
 wire oh,ov,od;wire [23:0] rgb;
 b_render render(pclk,prst,hs,vs,de,x,y,record_ui,plot,oh,ov,od,rgb,compact_plot[2] ? 7'd0:wave_read_data,wave_index,history_ready);
 hdmi_tx transmitter(pclk,sclk,prst,oh,ov,od,rgb,HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P);
endmodule
