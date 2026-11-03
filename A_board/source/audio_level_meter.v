`timescale 1ns/1ps
// Measure the audible PCM peak per video frame. Rise immediately and fall
// one cell per frame; meter_end=level+4 marks the first dark cell in 4..34.
module audio_level_meter(
 input wire clk,rst_n,sample_valid,frame,
 input wire [15:0] left,right,
 output reg [4:0] level,output reg [5:0] meter_end
);
 // Apply saturated x2 display gain to the L/R OR of one's-complement magnitudes.
 wire [5:0] ml=left[15] ? ~left[14:9]:left[14:9];
 wire [5:0] mr=right[15] ? ~right[14:9]:right[14:9];
 wire [5:0] m2=ml|mr;
 wire [4:0] mag=m2[5] ? 5'd31:m2[4:0];
 reg [4:0] peak;
 wire [4:0] next=peak>level ? peak:level!=0 ? level-1'b1:5'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin peak<=0;level<=0;meter_end<=4;end
  else if(frame)begin
   level<=next;meter_end<={1'b0,next}+6'd4;
   peak<=sample_valid ? mag:5'd0;
  end else if(sample_valid && mag>peak)peak<=mag;
 end
endmodule
