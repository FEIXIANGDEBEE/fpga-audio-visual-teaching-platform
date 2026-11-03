`timescale 1ns/1ps
// Q/I/P plus one board-specific view
// Other command bytes must leave the selected view alone
module debug_select #(parameter LAST_QUERY=8'h53)(
 input wire clk,rst_n,input wire [7:0] command,input wire command_valid,
 input wire [127:0] frame_q,frame_i,frame_p,frame_last,
 output reg [7:0] query,output reg [127:0] stats
);
 always @(posedge clk or negedge rst_n)
  if(!rst_n)query<="Q";
  else if(command_valid && (command=="Q" || command=="I" || command=="P" || command==LAST_QUERY))query<=command;
 always @*begin
  case(query)
   "I":stats=frame_i;
   "P":stats=frame_p;
   LAST_QUERY:stats=frame_last;
   default:stats=frame_q;
  endcase
 end
endmodule
