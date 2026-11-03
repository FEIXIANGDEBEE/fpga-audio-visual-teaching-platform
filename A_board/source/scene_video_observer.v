`timescale 1ns/1ps
// Hold the pixel ID until the next first visible pixel with a new ID.
// SYS compares it after the two-stage toggle capture.
module scene_video_observer(
 input wire pclk,prst_n,de,input wire [9:0] x,y,input wire active,input wire [31:0] active_id,
 input wire sys_clk,sys_rst_n,waiting,input wire [31:0] target_id,
 output reg committed
);
 reg observed_toggle;reg [31:0] observed_id;
 (* ASYNC_REG="TRUE" *) reg observed_m,observed_s;reg observed_seen;
 always @(posedge pclk or negedge prst_n)
  if(!prst_n)begin observed_toggle<=0;observed_id<=0;end
  else if(de && x==0 && y==0 && active && active_id!=observed_id)begin
   observed_id<=active_id;observed_toggle<=~observed_toggle;
  end
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin observed_m<=0;observed_s<=0;observed_seen<=0;committed<=0;end
  else begin
   observed_m<=observed_toggle;observed_s<=observed_m;observed_seen<=observed_s;
   committed<=(observed_s!=observed_seen) && waiting && observed_id==target_id;
  end
 end
endmodule
