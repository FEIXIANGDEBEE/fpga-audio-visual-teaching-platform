`timescale 1ns/1ps
// Three common queries plus a board-specific query select diagnostics.
// Unsupported queries preserve the current view; HAS_I=0 disables I on A.
module debug_select #(parameter LAST_QUERY=8'h53,parameter HAS_I=1)(
 input wire clk,rst_n,input wire [7:0] command,input wire command_valid,
 input wire [127:0] frame_q,frame_i,frame_p,frame_last,
 output reg [7:0] query,output reg [127:0] stats
);
 always @(posedge clk or negedge rst_n)
  if(!rst_n)query<="Q";
  else if(command_valid && (command=="Q" || HAS_I && command=="I" || command=="P" || command==LAST_QUERY))query<=command;
 always @*begin
  case(query)
   "P":stats=frame_p;
   LAST_QUERY:stats=frame_last;
   "I":stats=HAS_I ? frame_i:frame_q;
   default:stats=frame_q;
  endcase
 end
endmodule
