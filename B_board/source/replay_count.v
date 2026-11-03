`timescale 1ns/1ps
// Count completed replay frames. clear restarts the count; busy reports replay ownership.
module replay_count(
 input wire sys_clk,sys_rst_n,mclk,audio_rst_n,clear,frame_valid,
 input wire [31:0] frame,output wire [31:0] completed_frames
);
 wire [31:0] total_frames;
 pcm_witness witness(.clk(mclk),.rst_n(audio_rst_n),.clear(clear),
  .frame_valid(frame_valid),.frame(frame),.window_valid(),.window_id(),
  .base_frame(),.window_crc(),.total_frames(total_frames),.overruns());
 cdc_snapshot #(.WIDTH(32)) snapshot(mclk,audio_rst_n,total_frames,
  sys_clk,sys_rst_n,1'b1,completed_frames);
endmodule
