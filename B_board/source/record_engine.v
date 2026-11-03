`timescale 1ns/1ps
`include "record_params.vh"
// SYS owns the recording store; MCLK reads finite replay from the same RAM.
// The replay command stays held until the last wire frame completes.
module record_engine #(parameter FRAMES=`BASIC_FRAMES,TEMPLATE="record_template.dath")(
 input wire clk,rst_n,enabled,media_fault,command_valid,input wire [3:0] command,output wire command_ready,
 input wire mic_valid,input wire [34:0] mic_data,input wire mic_alive,mic_warmed,
 output wire has_record,can_record,io_quiescent,output wire [3:0] backend_state,
 output wire [7:0] error_code,output wire clipped,output wire [31:0] pcm_bytes,output wire [22:0] samples,
 output wire sector_request,output wire [31:0] sector_lba,output wire sector_write,
 input wire sector_ready,sector_accepted,input wire [7:0] sector_data,input wire sector_valid,sector_complete,sector_error,
 input wire [8:0] write_address,output wire [7:0] write_data,input wire [32:0] card_sectors,
 input wire mclk,audio_rst_n,output wire can_play,replay_select,replay_valid,
 output wire [31:0] replay_frame,input wire replay_take,replay_boundary,output wire replay_begin,
 output wire memory_write,output wire [13:0] memory_address,output wire [7:0] memory_data,
 input wire [7:0] memory_read,play_read,output wire [13:0] playback_address,output wire ui_save_committed,ui_slot_ready,output wire [4:0] ui_save_progress,output wire ui_saved
);
 assign ui_slot_ready=slot_ready;
 wire start_ready,slot_ready,saved,store_quiet,load_done;wire [31:0] record_epoch;
 assign ui_saved=saved;
 wire [7:0] store_error,play_data;wire [3:0] store_state;wire [13:0] play_address;
 assign playback_address=play_address;assign play_data=play_read;
 wire srst_n,drst_n;
 reset_sync replay_sys_reset(clk,rst_n && audio_rst_n,srst_n);
 reset_sync replay_audio_reset(mclk,rst_n && audio_rst_n,drst_n);
 localparam IDLE=0,LOAD=1,SEND=2,PLAY=3;
 reg [1:0] replay_phase;reg stop_request;
 wire accepted=command_valid && command_ready;
 wire stop=accepted && command==2 || !enabled || media_fault;
 assign can_record=start_ready && replay_phase==IDLE && !media_fault;
 assign can_play=enabled && srst_n && slot_ready && has_record && store_quiet && replay_phase==IDLE && !media_fault;
 assign command_ready=enabled && (command==1 ? can_record:command==2 ? 1'b1:command==3 && can_play);
 assign backend_state=media_fault || store_state==9 || store_state==0 && store_error!=0 ? 4'd9:
  replay_phase==PLAY ? 4'd6:replay_phase!=IDLE ? 4'd5:store_state;
 assign error_code=media_fault ? 8'h70:store_error;
 assign io_quiescent=store_quiet && replay_phase==IDLE;
 wire mail_ready,mail_done,play_command,play_ack;wire play_word;
 scene_cdc_mailbox #(.WIDTH(1)) play_commands(clk,srst_n,replay_phase==SEND && !stop_request && !stop,
  pcm_bytes!=4002,mail_ready,mail_done,mclk,drst_n,play_command,play_word,play_ack);
 (* ASYNC_REG="TRUE" *)reg stop_meta,stop_sync;
 always @(posedge mclk or negedge drst_n)
  if(!drst_n)begin stop_meta<=0;stop_sync<=0;end
  else begin stop_meta<=stop_request;stop_sync<=stop_meta;end
 always @(posedge clk or negedge srst_n)begin
  if(!srst_n)begin replay_phase<=IDLE;stop_request<=0;end
  else begin
   if(stop)stop_request<=1;
   case(replay_phase)
    IDLE:begin stop_request<=0;if(accepted && command==3)replay_phase<=LOAD;end
    LOAD:if((stop_request || stop) && store_quiet)replay_phase<=IDLE;
     else if(store_state==9 || store_quiet && (store_error!=0 || !has_record))replay_phase<=IDLE;
     else if(load_done)replay_phase<=(stop_request || stop) ? IDLE:SEND;
    SEND:if(stop_request || stop)replay_phase<=IDLE;else if(mail_ready)replay_phase<=PLAY;
    PLAY:if(mail_done)replay_phase<=IDLE;
   endcase
  end
 end
 ram_replay #(.NEW_FRAMES(FRAMES)) player(mclk,drst_n,play_command,play_word,play_ack,stop_sync,
  replay_boundary,replay_take,play_address,play_data,replay_select,replay_valid,replay_frame,replay_begin);
 slot_store #(.FRAMES(FRAMES),.TEMPLATE(TEMPLATE)) store(clk,rst_n,enabled,accepted && command==1,accepted && command==2,
  mic_valid,mic_data,mic_alive,mic_warmed,start_ready,slot_ready,has_record,store_state,
  store_error,saved,pcm_bytes,record_epoch,samples,clipped,
  sector_request,sector_lba,sector_write,sector_ready,sector_accepted,sector_data,
  sector_valid,sector_complete,sector_error,write_address,write_data,store_quiet,card_sectors,media_fault,
  accepted && command==3,load_done,memory_write,memory_address,memory_data,memory_read,ui_save_committed,ui_save_progress);
endmodule
