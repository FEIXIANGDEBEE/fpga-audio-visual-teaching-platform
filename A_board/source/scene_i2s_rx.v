`timescale 1ns/1ps
// Oversample the 64-BCLK/channel I2S stream in the pixel domain.
// After reset or a mid-channel start, wait for falling LRCK and then
// a complete left/right pair before publishing.
module scene_i2s_rx(
 input wire clk,rst_n,bclk,lrck,dout,
 output reg frame_valid,output reg [31:0] frame,
 output reg [31:0] frames,format_errors
);
 (* ASYNC_REG="TRUE" *) reg [2:0] bpipe,lpipe,dpipe;
 reg last_lrck,channel_seen,left_complete;
 reg [6:0] bits;
 reg [63:0] left_shift,right_shift,left_lock;
 wire rise=!bpipe[2] && bpipe[1];
 // LRCK and DATA change at falling BCLK. Match their three input stages;
 // the first sampled bit is the I2S delay bit.
 wire change=lpipe[2]!=last_lrck;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   bpipe<=0;lpipe<=0;dpipe<=0;last_lrck<=0;channel_seen<=0;
   left_complete<=0;bits<=0;left_shift<=0;right_shift<=0;left_lock<=0;
   frame_valid<=0;frame<=0;frames<=0;format_errors<=0;
  end else begin
   bpipe<={bpipe[1:0],bclk};lpipe<={lpipe[1:0],lrck};dpipe<={dpipe[1:0],dout};
   frame_valid<=0;
   if(rise)begin
    last_lrck<=lpipe[2];
    if(change)begin
     // The edge with changed LRCK contains the previous channel's last padding
     // bit, so it completes that channel.
     if(!lpipe[2])begin
      if(channel_seen && left_complete && bits==63)begin
       frame<={right_shift[62:47],left_lock[63:48]};frame_valid<=1;frames<=frames+1'b1;
      end else if(channel_seen && left_complete)format_errors<=format_errors+1'b1;
      channel_seen<=1;left_complete<=0;bits<=0;left_shift<=0;right_shift<=0;
     end else begin
      left_complete<=channel_seen && bits==63;
      if(channel_seen && bits!=63)format_errors<=format_errors+1'b1;
      left_lock<={left_shift[62:0],dpipe[2]};bits<=0;right_shift<=0;
     end
    end else if(channel_seen)begin
     if(bits!=127)bits<=bits+1'b1;
     if(last_lrck)right_shift<={right_shift[62:0],dpipe[2]};
     else left_shift<={left_shift[62:0],dpipe[2]};
    end
   end
  end
 end
endmodule
