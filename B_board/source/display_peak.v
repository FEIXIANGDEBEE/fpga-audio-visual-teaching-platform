`timescale 1ns/1ps
// Scan the same frozen heights as motion; this is a display result only
module display_peak(
 input wire clk,rst_n,frame_start,valid,wave,held,
 input wire [5:0] identity,input wire [3:0] page,input wire [127:0] raw_heights,
 output reg [3:0] peak_band
);
 reg [5:0] previous_identity;reg [3:0] previous_page,index,best_band;
 reg was_valid,was_wave,busy;reg [7:0] best_height;
 wire changed=!was_valid || was_wave || previous_identity!=identity || previous_page!=page;
 wire [7:0] target=raw_heights[index*8+:8];
 // Strict > keeps the first (lowest) band on a tie. The 16-cycle scan
 // finishes well before row160, without adding an FFT consumer or CDC.
 wire better=target>best_height;
 always @(posedge clk)begin
  if(!rst_n)begin peak_band<=0;previous_identity<=0;previous_page<=0;index<=0;best_band<=0;best_height<=0;was_valid<=0;was_wave<=0;busy<=0;end
  else if(frame_start)begin
   previous_identity<=identity;previous_page<=page;was_valid<=valid;was_wave<=wave;index<=0;best_band<=0;best_height<=0;
   if(!valid || wave)begin peak_band<=0;busy<=0;end
   else busy<=changed || !held;
  end else if(busy)begin
   if(better)begin best_height<=target;best_band<=index;end
   if(index==15)begin peak_band<=better ? index:best_band;busy<=0;end
   else index<=index+1'b1;
  end
 end
endmodule
