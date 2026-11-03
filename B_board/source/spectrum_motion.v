`timescale 1ns/1ps
// The snapshot stays fixed from vertical blank through the frame. Sixteen
// display updates finish by row 0, x=17; graph consumption starts at row 160.
// These updates affect only display motion, leaving FFT/PCM data unchanged.
module spectrum_motion(
 input wire clk,rst_n,frame_start,valid,wave,held,
 input wire [5:0] identity,input wire [3:0] page,input wire [127:0] raw_heights,
 output reg [127:0] heights,peaks
);
 reg [5:0] previous_identity;reg [3:0] previous_page,index;
 reg was_valid,was_wave,busy,snap;
 wire changed=!was_valid || was_wave || previous_identity!=identity || previous_page!=page;
 wire [7:0] target=raw_heights[index*8+:8];
 wire [7:0] old_height=heights[index*8+:8],old_peak=peaks[index*8+:8];
 wire [7:0] difference=old_height-target;
 wire [7:0] falling_step={2'b00,difference[7:2]}+{7'd0,(|difference[1:0])};
 wire [7:0] next_height=snap || target>=old_height ? target:old_height-falling_step;
 wire [7:0] decayed_peak=old_peak==0 ? 8'd0:old_peak-1'b1;
 wire [7:0] next_peak=snap || next_height>=decayed_peak ? next_height:decayed_peak;
 always @(posedge clk)begin
  if(!rst_n)begin heights<=0;peaks<=0;previous_identity<=0;previous_page<=0;index<=0;was_valid<=0;was_wave<=0;busy<=0;snap<=0;end
  else if(frame_start)begin
   previous_identity<=identity;previous_page<=page;was_valid<=valid;was_wave<=wave;index<=0;snap<=changed;
   if(!valid || wave)begin busy<=0;end
   else busy<=changed || !held;
  end else if(busy)begin
   heights[index*8+:8]<=next_height;peaks[index*8+:8]<=next_peak;
   if(index==15)busy<=0;else index<=index+1'b1;
  end
 end
endmodule
