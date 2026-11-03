`timescale 1ns/1ps
// load_valid marks the FIFO take at the frame boundary. Registered frame_done
// and commit_applied describe that boundary; the loaded frame completes at
// the next boundary, including muted frames.
module scene_playback_position(
 input wire clk,rst_n,frame_done,load_valid,commit_applied,
 input wire [31:0] commit_frames,output wire [159:0] stats,
 output wire [31:0] record_length,output reg [31:0] restart_generation
);
 reg pending_take,loaded_take;
 reg [31:0] output_frames,consumed_frames,song_frames,position,loops,length;
 assign stats={output_frames,consumed_frames,song_frames,position,loops};
  assign record_length=length;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   pending_take<=0;loaded_take<=0;output_frames<=0;consumed_frames<=0;
   song_frames<=0;position<=0;loops<=0;length<=0;restart_generation<=0;
  end else begin
   pending_take<=load_valid;
   if(frame_done)begin
    output_frames<=output_frames+1'b1;
    loaded_take<=pending_take;
    if(loaded_take)begin
     consumed_frames<=consumed_frames+1'b1;song_frames<=song_frames+1'b1;
     if(length!=0 && position==length-1)begin position<=0;loops<=loops+1'b1;end
     else position<=position+1'b1;
    end
    if(commit_applied)begin
      song_frames<=0;position<=0;loops<=0;length<=commit_frames;restart_generation<=restart_generation+1'b1;
    end
   end
  end
 end
endmodule
