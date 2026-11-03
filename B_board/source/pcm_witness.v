`timescale 1ns/1ps
// Completed I2S frames arrive 256 MCLK cycles apart. CRC consumes 32 LSB-first
// bits in 32 cycles without backpressure. total_frames updates on acceptance;
// window_crc is published after the last bit of the window has been processed.
module pcm_witness #(parameter WINDOW_FRAMES=512)(
 input wire clk,rst_n,clear,frame_valid,input wire [31:0] frame,
 output reg window_valid,output reg [31:0] window_id,base_frame,window_crc,
 output reg [31:0] total_frames,overruns
);
 reg [31:0] crc,held;
 reg [5:0] phase;
 reg [8:0] count;
 wire [31:0] next_crc=(crc>>1)^((crc[0]^held[0]) ?32'hedb88320:32'd0);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   crc<=32'hffffffff;held<=0;phase<=0;count<=0;
   window_valid<=0;window_id<=0;base_frame<=0;window_crc<=0;total_frames<=0;overruns<=0;
  end else if(clear)begin
   crc<=32'hffffffff;held<=0;phase<=0;count<=0;
   window_valid<=0;window_id<=0;base_frame<=0;window_crc<=0;total_frames<=0;overruns<=0;
  end else begin
   window_valid<=0;
   if(frame_valid)begin
    if(phase!=0)overruns<=overruns+1'b1;
    else begin held<=frame;phase<=1;total_frames<=total_frames+1'b1;end
   end
   if(phase!=0)begin
    crc<=next_crc;held<={1'b0,held[31:1]};
    if(phase==32)begin
     phase<=0;
     if(count==WINDOW_FRAMES-1)begin
      count<=0;window_crc<=~next_crc;crc<=32'hffffffff;
      base_frame<=total_frames-WINDOW_FRAMES;window_valid<=1;window_id<=window_id+1'b1;
     end else count<=count+1'b1;
    end else phase<=phase+1'b1;
   end
  end
 end
endmodule
