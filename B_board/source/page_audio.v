`timescale 1ns/1ps
// Page identity, valid music and active bank are tracked separately.
// The MCLK side acknowledges a held configuration at a complete audio-frame boundary.
module page_audio(
 input wire clk,rst_n,initialized,hard_fault,
 input wire page_begin,input wire [3:0] target_page,current_page,
 input wire page_applied,pause,mute,
 input wire active_bank,input wire [12:0] count0,count1,
 input wire [63:0] lengths,input wire [1:0] quiescent,pcm_fault,
 output wire [1:0] feed,
 output wire clear_valid,clear_bank,input wire clear_ready,clear_done,
 output wire bind_valid,bind_bank,output wire [1:0] bind_scene,input wire bind_ready,bind_done,bind_error,
 output wire cfg_valid,output reg [5:0] cfg,input wire cfg_ready,cfg_done,
 output reg [31:0] cfg_frames,output reg [1:0] cfg_scene,
 output reg music_valid,output reg [1:0] music_id,output wire idle,
 output reg fault,output reg [31:0] commits,output wire [3:0] state_debug,input wire suspended
);
 localparam IDLE=0,PREP_SEND=1,PREP_WAIT=2,WAIT_IMAGE=3,CFG_SEND=4,CFG_WAIT=5;
 reg [2:0] state;reg image_seen,want_music,keep_position,target_bank;
 reg [1:0] target_music;reg [3:0] applied_control;
 reg cfg_is_page;
 wire target_has_music=target_page>=3 && target_page<=8;
 wire [1:0] target_song=target_page<=6 ? target_page-4'd3 : 2'd0;
 wire prep_accept,prep_done,prep_error;wire [12:0] prepared_count;
 wire [3:0] prep_state;wire [31:0] failed_prepares;
 wire commit_applied=state==CFG_WAIT && cfg_done && cfg[5];
 wire [3:0] desired_control={music_valid,pause,mute,hard_fault || fault};
 // A pending pause/mute update reserves the next config slot. Keep idle low
 // until it is sent, or a page pulse could be accepted on the CFG_SEND transition.
 assign idle=state==IDLE && !fault && initialized && desired_control==applied_control;
 assign state_debug={1'b0,state};
 assign cfg_valid=state==CFG_SEND && !suspended;
 scene_audio_prepare prepare(clk,rst_n,initialized && !suspended,hard_fault || fault,active_bank,music_valid,
  state==PREP_SEND,target_bank,target_music,prep_accept,prep_done,prep_error,prepared_count,
  feed,quiescent,pcm_fault,clear_valid,clear_bank,clear_ready,clear_done,
  bind_valid,bind_bank,bind_scene,bind_ready,bind_done,bind_error,count0,count1,
  commit_applied,cfg[4],prep_state,failed_prepares);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;image_seen<=0;want_music<=0;keep_position<=0;target_bank<=0;target_music<=0;
   applied_control<=0;cfg<=0;cfg_frames<=0;cfg_scene<=0;cfg_is_page<=0;
   music_valid<=0;music_id<=0;fault<=0;commits<=0;
  end else if(!suspended)begin
   if(page_applied)image_seen<=1;
   if(hard_fault || prep_error)fault<=1;
   case(state)
    IDLE:begin
     if(page_begin && initialized && !fault && !hard_fault)begin
      image_seen<=0;want_music<=target_has_music;target_music<=target_song;
      keep_position<=target_page==8 && current_page==7 && music_valid && music_id==0 && !pause;
      target_bank<=!active_bank;
      state<=target_has_music && !(target_page==8 && current_page==7 && music_valid && music_id==0 && !pause) ? PREP_SEND:WAIT_IMAGE;
     end else if(initialized && desired_control!=applied_control)begin
      cfg<={1'b0,active_bank,desired_control};cfg_scene<=music_id;cfg_is_page<=0;state<=CFG_SEND;
     end
    end
    PREP_SEND:if(prep_accept)state<=PREP_WAIT;
    PREP_WAIT:if(prep_done)begin if(prep_error)fault<=1;else state<=WAIT_IMAGE;end
    WAIT_IMAGE:if(image_seen || page_applied)begin
     cfg<={want_music && !keep_position,keep_position ? active_bank:target_bank,want_music,pause,mute,hard_fault || fault};
     cfg_scene<=target_music;cfg_frames<=target_bank ? lengths[63:32]:lengths[31:0];
     cfg_is_page<=1;state<=CFG_SEND;
    end
    CFG_SEND:if(cfg_ready)state<=CFG_WAIT;
    CFG_WAIT:if(cfg_done)begin
     applied_control<=cfg[3:0];state<=IDLE;
     if(cfg_is_page)begin music_valid<=want_music;music_id<=target_music;if(cfg[5])commits<=commits+1'b1;end
    end
    default:begin fault<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
