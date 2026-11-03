`timescale 1ns/1ps
// 64 BCLKs per channel, one I2S delay bit and 24 significant bits.
// Hold MCLK-synchronous controls to the L/R boundary. COMMIT selects the
// new bank's first unread frame once at that boundary.
module scene_i2s_tx(
 input wire mclk,rst_n,enable,pause,mute,fault,
 input wire commit,target_bank,
 input wire [31:0] frame0,frame1,input wire valid0,valid1,
 output wire take0,take1,output reg active_bank,output reg applied,
 output reg bclk,lrck,dout,output reg underflow,
 output reg sent_valid,output reg [31:0] sent_frame,
 output reg [31:0] output_frames,consumed_frames,input wire calibrate,
 input wire config_valid,output reg config_applied,
 input wire [1:0] config_scene,output reg [6:0] sent_tag,
 output reg [31:0] consumed_frame,
 input wire [3:0] volume_level,input wire [7:0] volume_generation,input wire volume_valid,
 output wire volume_ack,output wire [21:0] volume_status,output reg [12:0] sent_volume,
 input wire replay_select,replay_valid,input wire [31:0] replay_frame,
 output wire replay_take,replay_boundary
);
 reg [5:0] bit_count;
 reg [63:0] shift;
 reg [31:0] current_frame,current_source;
 // Tag the frame just completed on the wire:
 // {scene,enable,calibrate_or_replay,fault,mute,pause}. cfg_calibrate is tied
 // low in production; recording ownership identifies replay in bit 3.
 reg [6:0] current_tag;
 reg [3:0] current_volume;reg [7:0] volume_epoch;reg [8:0] actual_gain;reg [12:0] current_volume_tag;
 function [8:0] coefficient;input [3:0] level;begin
 case(level)0:coefficient=0;1:coefficient=6;2:coefficient=10;3:coefficient=16;4:coefficient=26;
 5:coefficient=41;6:coefficient=64;7:coefficient=102;8:coefficient=161;9:coefficient=256;default:coefficient=102;endcase
 end endfunction
 wire boundary=bclk && bit_count==63 && lrck;
 wire selected_bank=commit ? target_bank : active_bank;
 wire selected_valid=replay_select ? replay_valid:(selected_bank ? valid1 : valid0);
 wire [31:0] selected_frame=replay_select ? replay_frame:(selected_bank ? frame1 : frame0);
 wire output_enable=enable || replay_select;
 wire output_pause=pause && !replay_select;
 assign replay_boundary=boundary;
 wire [3:0] next_level=volume_valid ? (volume_level<=9 ? volume_level:4'd7):current_volume;
 wire [8:0] goal_gain=coefficient(next_level);
 wire gain_allowed=output_enable && !output_pause && !mute && !fault && !underflow && !calibrate && selected_valid;
 wire [8:0] next_gain=!gain_allowed ? 9'd0:actual_gain<goal_gain ? actual_gain+1'b1:actual_gain>goal_gain ? actual_gain-1'b1:actual_gain;
 wire [31:0] scaled_frame;
 pcm_gain scaler(selected_frame,next_gain,scaled_frame);
 assign volume_ack=boundary && volume_valid;
 assign volume_status={volume_epoch,current_volume,actual_gain,(gain_allowed && actual_gain!=goal_gain)};
 wire consume=boundary && output_enable && !output_pause && !fault && !underflow && !calibrate && selected_valid;
 reg [31:0] calibration_index;
 wire [15:0] calibration_left=calibration_index[15:0]*16'd337+16'd17;
 wire [15:0] calibration_right=calibration_index[15:0]*16'd197+16'd12345;
 wire [31:0] calibration_frame=calibration_index==0 ? 32'h5aa5c33c : {calibration_right,calibration_left};
 assign take0=consume && !selected_bank && !replay_select;
 assign take1=consume && selected_bank && !replay_select;
 assign replay_take=consume && replay_select;
 always @(posedge mclk or negedge rst_n)begin
  if(!rst_n)begin
   bit_count<=0;shift<=0;current_frame<=0;active_bank<=0;applied<=0;
   bclk<=0;lrck<=0;dout<=0;underflow<=0;sent_valid<=0;sent_frame<=0;
   output_frames<=0;consumed_frames<=0;calibration_index<=0;config_applied<=0;current_tag<=0;sent_tag<=0;current_source<=0;consumed_frame<=0;current_volume<=7;volume_epoch<=0;actual_gain<=0;current_volume_tag<=0;sent_volume<=0;
  end else begin
   sent_valid<=0;applied<=0;config_applied<=0;bclk<=~bclk;
   if(bclk)begin
    dout<=shift[63];shift<={shift[62:0],1'b0};
    if(bit_count==63)begin
     bit_count<=0;
     if(!lrck)begin lrck<=1;shift<={current_frame[31:16],48'd0};end
     else begin
      lrck<=0;sent_volume<=current_volume_tag;actual_gain<=next_gain;
      current_volume_tag<={volume_valid ? volume_generation:volume_epoch,next_level,(gain_allowed && next_gain==goal_gain)};
      if(volume_valid)begin current_volume<=next_level;volume_epoch<=volume_generation;end
      sent_valid<=1;sent_frame<=current_frame;consumed_frame<=current_source;sent_tag<=current_tag;output_frames<=output_frames+1'b1;
      current_tag<={config_scene,replay_select ? replay_valid:enable,calibrate || replay_select,fault || underflow,mute,output_pause};
      if(config_valid)config_applied<=1;
      if(commit)begin active_bank<=target_bank;applied<=1;end
      if(calibrate && !fault && !underflow)begin
       calibration_index<=calibration_index+1'b1;current_frame<=calibration_frame;current_source<=0;
       shift<={calibration_frame[15:0],48'd0};
      end else if(consume)begin
       calibration_index<=0;
       consumed_frames<=consumed_frames+1'b1;
       current_frame<=mute ? 32'd0 : scaled_frame;current_source<=selected_frame;
       shift<=mute ? 64'd0 : {scaled_frame[15:0],48'd0};
      end else begin
       calibration_index<=0;current_frame<=0;current_source<=0;shift<=0;
       if(enable && !replay_select && !pause && !fault && !underflow && !calibrate && !selected_valid)underflow<=1;
      end
     end
    end else bit_count<=bit_count+1'b1;
   end
  end
 end
endmodule
