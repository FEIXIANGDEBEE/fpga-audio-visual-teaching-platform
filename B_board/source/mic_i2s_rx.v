`timescale 1ns/1ps
// INMP441 with LR=0: MCLK enables sample SD; SCK is an output, not a fabric clock.
// WS changes at the falling SCK edge. Skip the I2S dummy bit, then collect 24 bits MSB first.
module mic_i2s_rx #(parameter WARMUP_FRAMES=4096)(
 input wire mclk,rst_n,sd,output reg sck,ws,
 output reg valid,output reg signed [23:0] raw,
 output reg [15:0] sample_sequence,output reg warmed);
 reg [1:0] phase;reg [5:0] slot;reg [12:0] warm_frames;
 reg [23:0] shift;
 always @(posedge mclk or negedge rst_n)begin
  if(!rst_n)begin phase<=0;slot<=63;sck<=0;ws<=1;valid<=0;raw<=0;sample_sequence<=0;warmed<=0;warm_frames<=0;shift<=0;end
  else begin
   phase<=phase+1'b1;valid<=0;
   if(phase==0)begin
    sck<=0;slot<=slot+1'b1;
    ws<=slot==63 ? 0 : slot==31 ? 1 : ws;
    if(slot==63)begin
     if(warm_frames<WARMUP_FRAMES)warm_frames<=warm_frames+1'b1;
     else warmed<=1;
    end
   end
   if(phase==2)begin
    sck<=1;
    if(slot>=1 && slot<=24)begin
     shift<={shift[22:0],sd};
     if(slot==24 && warmed)begin raw<={shift[22:0],sd};valid<=1;sample_sequence<=sample_sequence+1'b1;end
    end
   end
  end
 end
endmodule
