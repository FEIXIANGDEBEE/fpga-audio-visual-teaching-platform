`timescale 1ns/1ps
// Source changes wait for a window boundary; a gap discards the partial window
module analysis_source #(parameter GAP_CYCLES=1000000)(
 input wire clk,rst_n,request_mic,input wire [1:0] request_gain,
 input wire play_valid,input wire [38:0] play_data,input wire [3:0] play_identity,
 input wire mic_valid,input wire [34:0] mic_data,input wire mic_alive,mic_warmed,
 output reg frame_valid,output reg [31:0] frame,output reg [6:0] tag,
 output reg [2:0] frame_context,output wire [31:0] frame_generation,
 output reg abort_window,output reg active_mic,output reg [1:0] active_gain,
 output reg [31:0] generation,discontinuities,switch_aborts,clip_samples,
 output wire waiting,input wire [7:0] play_gain_epoch,input wire play_gain_stable,
 // Latch the MIC record boost with the source/gain switch. Otherwise one
 // window could contain both amplitudes.
 input wire request_boost);
 reg [8:0] pos;reg [19:0] age;reg [15:0] expected_sequence;reg have_sequence;
 reg [7:0] previous_gain_epoch;reg active_boost;
 wire gain_boundary=!active_mic && play_valid && (!play_gain_stable || play_gain_epoch!=previous_gain_epoch);
 reg [3:0] previous_play_identity;reg previous_mic_alive;
 wire change=request_mic!=active_mic || (active_mic && (request_gain!=active_gain || request_boost!=active_boost)) || (!active_mic && play_identity!=previous_play_identity);
 wire [15:0] mic_pcm=mic_data[15:0];
 wire [15:0] boosted=mic_pcm[15]!=mic_pcm[14] ? (mic_pcm[15] ? 16'h8000:16'h7fff):{mic_pcm[14:0],1'b0};
 wire mv=mic_valid && mic_alive && mic_warmed;
 wire sample_valid=active_mic ? mv && mic_data[18:17]==active_gain : play_valid;
 wire gap=active_mic && mv && have_sequence && mic_data[34:19]!=expected_sequence;
 assign frame_generation=generation;
 assign waiting=gain_boundary || change || (active_mic && (!mic_alive || !mic_warmed));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin frame_valid<=0;frame<=0;tag<=0;frame_context<=0;abort_window<=0;active_mic<=0;active_gain<=0;active_boost<=0;generation<=0;pos<=0;age<=0;expected_sequence<=16'd1;have_sequence<=0;discontinuities<=0;switch_aborts<=0;clip_samples<=0;previous_play_identity<=0;previous_mic_alive<=0;previous_gain_epoch<=0;end
  else begin
   frame_valid<=0;abort_window<=0;previous_mic_alive<=mic_alive;
   if(play_valid)previous_gain_epoch<=play_gain_epoch;
   if(sample_valid)age<=0;else if(age<GAP_CYCLES)age<=age+1'b1;
   if(active_mic && sample_valid)begin expected_sequence<=mic_data[34:19]+16'd1;have_sequence<=1;end
   if(gain_boundary)begin
    abort_window<=1;pos<=0;generation<=generation+1'b1;age<=0;
   end else if(change && pos==0)begin
    active_mic<=request_mic;active_gain<=request_mic ? request_gain : 0;active_boost<=request_mic && request_boost;generation<=generation+1'b1;
    abort_window<=1;have_sequence<=0;age<=0;previous_play_identity<=play_identity;
   end else if((active_mic && previous_mic_alive && !mic_alive) || gap || (age==GAP_CYCLES-1 && (pos!=0 || change)))begin
    abort_window<=1;pos<=0;generation<=generation+1'b1;age<=0;have_sequence<=0;
    if(gap)discontinuities<=discontinuities+1'b1;
    else begin discontinuities<=discontinuities+1'b1;if(change)switch_aborts<=switch_aborts+1'b1;end
   end else if(sample_valid)begin
    frame_valid<=1;pos<=pos+1'b1;
    frame<=active_mic ? {16'd0,active_boost ? boosted:mic_pcm} : play_data[31:0];
    tag<=active_mic ? 7'b0010000 : play_data[38:32];frame_context<=active_mic ? {1'b1,active_gain} : 0;
    if(active_mic && mic_data[16])clip_samples<=clip_samples+1'b1;
   end
  end
 end
endmodule
