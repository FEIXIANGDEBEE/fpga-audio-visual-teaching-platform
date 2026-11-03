`timescale 1ns/1ps
// Quiesce the old source before clearing the inactive FIFO in both domains.
// Drain partial frames and pending bytes before clear/bind; the active bank
// continues to feed audio during preparation.
module scene_audio_prepare #(parameter TIMEOUT_CYCLES=50000000)(
 input wire clk,rst_n,initialized,hard_fault,input wire active_bank,current_valid,
 input wire prepare_valid,prepare_bank,input wire [1:0] prepare_scene,output wire prepare_accept,
 output reg prepare_done,prepare_error,output wire [12:0] prepared_count,
 output reg [1:0] feed_enable,input wire [1:0] context_quiescent,pcm_fault,
 output wire clear_valid,clear_bank,input wire clear_ready,clear_done,
 output wire bind_valid,bind_bank,output wire [1:0] bind_scene,input wire bind_ready,bind_done,bind_error,
 input wire [12:0] count0,count1,
 input wire commit_applied,committed_bank,
 output reg [3:0] state,output reg [31:0] failed_prepares
);
 localparam IDLE=0,QUIESCE=1,CLEAR_SEND=2,CLEAR_WAIT=3,BIND_SEND=4,BIND_WAIT=5,FILL=6,HOLD_READY=7;
 reg bank;reg [1:0] scene;reg [31:0] timer;
 assign prepare_accept=state==IDLE && initialized && !hard_fault;
 assign prepared_count=bank ? count1 : count0;
 assign clear_valid=state==CLEAR_SEND && clear_ready;
 assign clear_bank=bank;
 assign bind_valid=state==BIND_SEND && bind_ready;
 assign bind_bank=bank;assign bind_scene=scene;
 task reject;
  begin prepare_done<=1;prepare_error<=1;feed_enable[bank]<=0;state<=IDLE;failed_prepares<=failed_prepares+1'b1;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;bank<=0;scene<=0;timer<=0;feed_enable<=0;prepare_done<=0;prepare_error<=0;failed_prepares<=0;end
  else begin
   prepare_done<=0;prepare_error<=0;
   if(state!=IDLE && state!=HOLD_READY)timer<=timer+1'b1;
   if(hard_fault)begin
    feed_enable<=0;
    if(state!=IDLE)reject();
   end else if(state!=IDLE && state!=HOLD_READY && timer>=TIMEOUT_CYCLES-1)reject();
   else case(state)
    IDLE:begin
     timer<=0;
     if(prepare_valid && prepare_accept)begin
      bank<=prepare_bank;scene<=prepare_scene;
      if(current_valid && prepare_bank==active_bank)begin prepare_done<=1;prepare_error<=1;failed_prepares<=failed_prepares+1'b1;end
      else begin feed_enable[prepare_bank]<=0;state<=QUIESCE;end
     end
    end
    QUIESCE:if(context_quiescent[bank])state<=CLEAR_SEND;
    CLEAR_SEND:if(clear_valid && clear_ready)state<=CLEAR_WAIT;
    CLEAR_WAIT:if(clear_done)state<=BIND_SEND;
    BIND_SEND:if(bind_valid && bind_ready)state<=BIND_WAIT;
    BIND_WAIT:if(bind_done)begin
     if(bind_error)reject();else begin feed_enable[bank]<=1;state<=FILL;end
    end
    FILL:begin
     if(pcm_fault[bank])reject();
     else if(prepared_count>=3072)begin prepare_done<=1;state<=HOLD_READY;end
    end
    HOLD_READY:if(pcm_fault[bank])reject();
    default:reject();
   endcase
   if(commit_applied && !hard_fault)begin
    // After commit, only the new bank may produce. Drain the old bank
    // before allowing its next clear/bind.
    feed_enable<=committed_bank ? 2'b10 : 2'b01;
    if(state==HOLD_READY && committed_bank==bank)state<=IDLE;
   end
  end
 end
endmodule
