`timescale 1ns/1ps
// Retain ownership through SD binding, loading, playback and final drain.
module record_mode(
 input wire clk,rst_n,start_event,eligible,cancel_key,leave_request,
 input wire [3:0] backend_state,input wire can_record,io_quiescent,
 output reg owner,output wire command_valid,output wire [3:0] command,
 input wire command_ready,output wire [2:0] mode_state,
 input wire play_event,can_play,
 input wire preflight_event,preflight_confirm,preflight_cancel,output reg preflight_active,input wire save_complete
);
 localparam BIND=0,RUN=1,DONE=2,EXIT=3;
 reg [1:0] phase;reg want_play;
 wire stop=cancel_key || leave_request || preflight_active && preflight_cancel;
 wire request_play=phase==BIND ? want_play:play_event;
 wire begin_job=owner && (phase==BIND || phase==DONE && (start_event || play_event)) && !stop &&
  (!preflight_active || preflight_confirm) &&
  (request_play ? can_play:can_record);
 assign mode_state=owner ? {1'b0,phase}+3'd1:3'd0;
 assign command_valid=begin_job || owner && ((phase==RUN && (stop || play_event && backend_state==6)) || phase==EXIT);
 assign command=begin_job ? (request_play ? 4'd3:4'd1):4'd2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin owner<=0;phase<=BIND;want_play<=0;preflight_active<=0;end
  else if(!owner)begin
   if((start_event || play_event || preflight_event) && eligible && !stop)begin owner<=1;phase<=BIND;want_play<=!preflight_event && play_event;preflight_active<=preflight_event;end
  end else begin
   case(phase)
    BIND:if((backend_state==9 || want_play && backend_state==1 && !can_play) && io_quiescent)phase<=DONE;
     else if(command_valid && command_ready)begin phase<=RUN;preflight_active<=0;end
    RUN:if(save_complete)phase<=EXIT;
     else if((backend_state==1 || backend_state==9) && io_quiescent)phase<=DONE;
    DONE:if(command_valid && command_ready)phase<=RUN;
    EXIT:if(io_quiescent)begin owner<=0;preflight_active<=0;end
   endcase
   if(phase!=EXIT && stop)phase<=EXIT;
  end
 end
endmodule
