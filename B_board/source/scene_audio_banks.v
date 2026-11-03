`timescale 1ns/1ps
// SYS produces and controls both banks; A supplies MCLK. A bank clear resets
// both Gray-pointer endpoints. Writes resume after both reset releases are seen.
module scene_audio_banks(
 input wire sys_clk,sys_rst_n,mclk,run,recover,
 input wire clear_valid,clear_bank,output wire clear_ready,output reg clear_done,
 input wire push,push_bank,input wire [31:0] push_frame,output wire push_ready,
 output wire [12:0] count0,count1,
 input wire cfg_valid,input wire [5:0] cfg,output wire cfg_ready,output wire cfg_done,
 output wire active_bank,bclk,lrck,dout,output wire audio_rst_n,
 output wire sent_valid,output wire [31:0] sent_frame,output wire underflow,
 output wire clock_alive,clock_fault,output wire [31:0] clock_events,
 output reg [31:0] illegal_operations,
 input wire [31:0] cfg_frames,output wire [159:0] playback_stats,input wire cfg_calibrate,
 input wire [1:0] cfg_scene,output wire [6:0] sent_tag,output wire commit_pulse,output wire [31:0] consumed_frame,
 output wire [66:0] progress_record,output reg [31:0] progress_expected_generation,
 input wire [3:0] volume_target,input wire [7:0] volume_generation,
 output wire [21:0] volume_status,output wire [12:0] sent_volume,
 input wire replay_select,replay_valid,input wire [31:0] replay_frame,
 output wire replay_take,replay_boundary,input wire replay_begin,
 input wire record_owner,record_we,input wire [13:0] record_address,input wire [7:0] record_data,
 output wire [7:0] record_read,input wire [13:0] record_play_address,output wire [7:0] record_play_read,output wire record_owned_mclk
);
 wire wrst_n;
 (* ASYNC_REG="TRUE" *)reg borrow_meta,borrow_sync;
 assign record_owned_mclk=borrow_sync;
 always @(posedge mclk or negedge audio_rst_n)
  if(!audio_rst_n)begin borrow_meta<=0;borrow_sync<=0;end
  else begin borrow_meta<=record_owner;borrow_sync<=borrow_meta;end
 scene_audio_clock_guard guard(sys_clk,sys_rst_n,mclk,run,recover,audio_rst_n,wrst_n,clock_alive,clock_fault,clock_events);
 reg [1:0] bank_run,usable;
 reg clear_busy,clearing_bank;
 reg [3:0] clear_count;
 reg playing;
 (* ASYNC_REG="TRUE" *) reg ab1,ab2,r01,r02,r11,r12;
 wire w0,r0,w1,r1;
 reset_sync wreset0(sys_clk,wrst_n && bank_run[0],w0);
 reset_sync wreset1(sys_clk,wrst_n && bank_run[1],w1);
 reset_sync rreset0(mclk,audio_rst_n && bank_run[0],r0);
 reset_sync rreset1(mclk,audio_rst_n && bank_run[1],r1);
 wire full0,full1,valid0,valid1,take0,take1;
 wire [31:0] frame0,frame1;
 wire [12:0] rcount0,rcount1;
 assign push_ready=wrst_n && usable[push_bank] && !(push_bank ? full1 : full0);
 scene_pcm_fifo #(.SHARED_RECORD(1)) fifo0(sys_clk,w0,push && push_ready && !push_bank,push_frame,full0,count0,
  mclk,r0,take0,frame0,valid0,rcount0,record_owner,borrow_sync,record_we,record_address,record_data,record_read,record_play_address,record_play_read);
 scene_pcm_fifo fifo1(sys_clk,w1,push && push_ready && push_bank,push_frame,full1,count1,
  mclk,r1,take1,frame1,valid1,rcount1,1'b0,1'b0,1'b0,14'd0,8'd0,,14'd0,);
 wire cv,cd,mail_ready;wire [40:0] control_word;wire [5:0] control=control_word[5:0];
 wire [12:0] target_count=cfg[4] ? count1 : count0;
 assign cfg_ready=wrst_n && mail_ready && !clear_busy &&
  (!cfg[5] || (usable[cfg[4]] && (!cfg[3] || target_count>=3072)));
 scene_cdc_mailbox #(.WIDTH(41)) commands(sys_clk,wrst_n,cfg_valid && cfg_ready,{cfg_scene,cfg_calibrate,cfg_frames,cfg},mail_ready,cfg_done,mclk,audio_rst_n,cv,control_word,cd);
 reg [1:0] current_scene;
 reg [3:0] current_control;reg current_calibrate;
 wire applied,control_applied;
 wire volume_ready,volume_valid,volume_ack;wire [11:0] volume_word;wire [21:0] volume_mclk;
 reg volume_sent;reg [11:0] last_volume;
 wire need_volume=!volume_sent || last_volume!={volume_generation,volume_target};
 scene_cdc_mailbox #(.WIDTH(12)) volume_commands(sys_clk,wrst_n,need_volume && volume_ready,{volume_generation,volume_target},volume_ready,,mclk,audio_rst_n,volume_valid,volume_word,volume_ack);
 always @(posedge sys_clk or negedge wrst_n)
  if(!wrst_n)begin volume_sent<=0;last_volume<=0;end
  else if(need_volume && volume_ready)begin volume_sent<=1;last_volume<={volume_generation,volume_target};end
 cdc_snapshot #(.WIDTH(22)) volume_snapshot(mclk,audio_rst_n,volume_mclk,sys_clk,wrst_n,1'b1,volume_status);
 assign commit_pulse=applied || replay_begin;
 // cfg = {COMMIT,bank,enable,pause,mute,fault}; hold it until the audio-frame
 // boundary applies the configuration and acknowledges it.
 wire commit=cv && control[5];
 wire [3:0] selected_control=cv ? control[3:0] : current_control;
 assign cd=cv && control_applied;
 always @(posedge mclk or negedge audio_rst_n)
  if(!audio_rst_n)begin current_control<=0;current_calibrate<=0;current_scene<=0;end
  else if(cv && cd)begin current_control<=control[3:0];current_calibrate<=control_word[38];current_scene<=control_word[40:39];end
 wire [31:0] output_frames,consumed_frames;
 scene_i2s_tx serial(mclk,audio_rst_n,selected_control[3],selected_control[2],selected_control[1],selected_control[0],
  commit,control[4],frame0,frame1,valid0 && r0,valid1 && r1,take0,take1,active_bank,applied,
  bclk,lrck,dout,underflow,sent_valid,sent_frame,output_frames,consumed_frames,cv ? control_word[38] : current_calibrate,cv,control_applied,
  cv ? control_word[40:39] : current_scene,sent_tag,consumed_frame,volume_word[3:0],volume_word[11:4],volume_valid,volume_ack,volume_mclk,sent_volume,
  replay_select,replay_valid,replay_frame,replay_take,replay_boundary);
 // Position advances on completed wire frames, including muted music.
 // COMMIT selects the following frame, so the old frame finishes before the
 // new song position begins; FIFO production and serial prefetch do not count.
 wire [159:0] playback_mclk;wire [31:0] playback_length,playback_generation;
 scene_playback_position position(mclk,audio_rst_n,sent_valid,
  take0 || take1,applied,control_word[37:6],playback_mclk,playback_length,playback_generation);
 always @(posedge sys_clk or negedge wrst_n)
  if(!wrst_n)progress_expected_generation<=0;
  else if(cfg_valid && cfg_ready && cfg[5])progress_expected_generation<=progress_expected_generation+1'b1;
 cdc_snapshot #(.WIDTH(227)) playback_snapshot(mclk,audio_rst_n,
  {playback_generation,playback_length,current_scene,current_control[3],playback_mclk},
  sys_clk,wrst_n,1'b1,{progress_record,playback_stats});
 assign clear_ready=wrst_n && !clear_busy && mail_ready && !cfg_valid && (!playing || clear_bank!=ab2);
 always @(posedge sys_clk or negedge wrst_n)begin
  if(!wrst_n)begin
   bank_run<=0;usable<=0;clear_busy<=0;clearing_bank<=0;clear_count<=0;clear_done<=0;
   ab1<=0;ab2<=0;r01<=0;r02<=0;r11<=0;r12<=0;playing<=0;illegal_operations<=0;
  end else begin
   ab1<=active_bank;ab2<=ab1;r01<=r0;r02<=r01;r11<=r1;r12<=r11;clear_done<=0;
   if(cfg_valid && cfg_ready)playing<=cfg[3];
   if(clear_valid && !clear_ready)illegal_operations<=illegal_operations+1'b1;
   if(push && !push_ready)illegal_operations<=illegal_operations+1'b1;
   if(clear_valid && clear_ready)begin
    bank_run[clear_bank]<=0;usable[clear_bank]<=0;
    clear_busy<=1;clearing_bank<=clear_bank;clear_count<=0;
   end
   if(clear_busy)begin
    if(clear_count<8)clear_count<=clear_count+1'b1;
    else begin
     bank_run[clearing_bank]<=1;
     if((clearing_bank ? r12 && w1 : r02 && w0))begin
      usable[clearing_bank]<=1;clear_done<=1;clear_busy<=0;
     end
    end
   end
  end
 end
endmodule
