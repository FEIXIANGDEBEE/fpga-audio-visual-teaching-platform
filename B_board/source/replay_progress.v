`timescale 1ns/1ps
// Use the completed-wire-frame snapshot. After a replay starts, hide the old
// count until its clear is observed; no additional audio counter or CDC is needed.
module replay_progress(
 input wire clk,rst_n,request,legacy,input wire [31:0] completed,
 output wire [1:0] state,output wire [3:0] seconds,segments
);
 reg seen_zero;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)seen_zero<=0;
  else if(!request)seen_zero<=0;
  else if(completed==0)seen_zero<=1;
 wire qualified=request && seen_zero && !(|completed[31:18]);
 wire [17:0] n=completed[17:0];
 assign state=!request ? 2'd0:!qualified ? 2'd1:legacy ? 2'd3:2'd2;
 assign seconds=!qualified ? 4'd0:n>=18'd240140 ? 4'd5:n>=18'd192112 ? 4'd4:
  n>=18'd144084 ? 4'd3:n>=18'd96056 ? 4'd2:n>=18'd48028 ? 4'd1:4'd0;
 // Map integer elapsed seconds onto the fourteen bar marks.
 // The numeric time is derived from completed frames.
 assign segments=!qualified ? 4'd0:seconds>=5 ? 4'd14:(seconds<<1)+seconds;
endmodule
