`timescale 1ns/1ps
// Match session identity before registering diagnostics; this observation
// does not change recognition, admission or the audio window.
module voice_status(
 input wire clk,rst_n,arm,cancel,capture,blocked,input wire [2:0] ui_state,
 input wire [31:0] control_generation,window_control,
 input wire feature_event,input wire [31:0] feature_control,feature_energy,
 input wire feature_invalid,input wire [31:0] clips,drops,discontinuities,
 input wire feedback_valid,feedback_ok,
 output wire [3:0] reason,output wire [31:0] session_control,max_energy,
 output wire [7:0] good_frames,invalid_frames,
 output wire clipped,data_bad,cancelled,rejected);
 reg early_tracking;reg [2:0] early_ui;reg [31:0] early_session;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin early_tracking<=0;early_ui<=0;early_session<=0;end
  else begin
   early_ui<=ui_state;
   if(arm)begin early_tracking<=1;early_session<=control_generation;end
   else if(ui_state==0 && early_ui!=0)early_tracking<=0;
  end
 end
 reg [173:0] observation;
 always @(posedge clk)observation<={early_tracking && window_control==early_session && control_generation==early_session,
  control_generation==early_session,feature_control==early_session,
  arm,cancel,capture,blocked,ui_state,control_generation,feature_event,feature_energy,feature_invalid,
  clips,drops,discontinuities,feedback_valid,feedback_ok};
 wire identity_q,control_q,feature_q,arm_q,cancel_q,capture_q,blocked_q,event_q,invalid_q,feedback_q,ok_q;
 wire [2:0] ui_q;wire [31:0] generation_q,energy_q,clips_q,drops_q,discontinuities_q;
 assign {identity_q,control_q,feature_q,arm_q,cancel_q,capture_q,blocked_q,ui_q,generation_q,event_q,energy_q,invalid_q,
  clips_q,drops_q,discontinuities_q,feedback_q,ok_q}=observation;
 voice_status_core core(clk,rst_n,arm_q,cancel_q,capture_q,blocked_q,ui_q,generation_q,32'd0,
  event_q,32'd0,energy_q,invalid_q,clips_q,drops_q,discontinuities_q,feedback_q,ok_q,
  reason,session_control,max_energy,good_frames,invalid_frames,clipped,data_bad,cancelled,rejected,identity_q,control_q,feature_q);
endmodule
`timescale 1ns/1ps
// Diagnostics only; no control feedback.
module voice_status_core(
 input wire clk,rst_n,arm,cancel,capture,blocked,input wire [2:0] ui_state,
 input wire [31:0] control_generation,window_control,
 input wire feature_event,input wire [31:0] feature_control,feature_energy,
 input wire feature_invalid,input wire [31:0] clips,drops,discontinuities,
 input wire feedback_valid,feedback_ok,
 output reg [3:0] reason,output reg [31:0] session_control,max_energy,
 output reg [7:0] good_frames,invalid_frames,
 output reg clipped,data_bad,cancelled,rejected,input wire qualified_identity,qualified_control,qualified_feature);
 reg tracking,was_capture;reg [2:0] old_ui;
 reg [31:0] last_clips,last_drops,last_discontinuities;
 wire identity_ok=qualified_identity;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   reason<=0;session_control<=0;max_energy<=0;good_frames<=0;invalid_frames<=0;
   clipped<=0;data_bad<=0;cancelled<=0;rejected<=0;tracking<=0;was_capture<=0;old_ui<=0;
   last_clips<=0;last_drops<=0;last_discontinuities<=0;
  end else begin
   old_ui<=ui_state;was_capture<=capture;
   if(arm)begin
    reason<=0;session_control<=control_generation;max_energy<=0;good_frames<=0;invalid_frames<=0;
    clipped<=0;data_bad<=0;cancelled<=0;rejected<=0;tracking<=1;was_capture<=0;
    last_clips<=clips;last_drops<=drops;last_discontinuities<=discontinuities;
   end else begin
    if(tracking && (cancel || !qualified_control))begin cancelled<=1;reason<=7;end
    if(identity_ok && capture && !cancel && !cancelled)begin
     last_clips<=clips;last_drops<=drops;last_discontinuities<=discontinuities;
     if(!was_capture)begin
      // Source ownership is ready; discard the prewarm history.
      last_clips<=clips;last_drops<=drops;last_discontinuities<=discontinuities;
     end else begin
      if(clips!=last_clips)clipped<=1;
      if(good_frames!=0 && (drops!=last_drops || discontinuities!=last_discontinuities))data_bad<=1;
     end
     if(feature_event && qualified_feature)begin
      if(feature_invalid)begin
       if(invalid_frames!=255)invalid_frames<=invalid_frames+1'b1;
       if(good_frames!=0)data_bad<=1;
      end else begin
       if(good_frames!=255)good_frames<=good_frames+1'b1;
       if(feature_energy>max_energy)max_energy<=feature_energy;
      end
     end
    end
    if(identity_ok && feedback_valid && !cancel && !cancelled)rejected<=!feedback_ok;
    if(ui_state==6 && old_ui!=6 && tracking)begin
     if(cancelled || cancel || !qualified_control)reason<=7;
     else if(blocked)reason<=1;
     else if(clipped)reason<=4;
     else if(data_bad || good_frames==0)reason<=6;
     else if(rejected)reason<=5;
     else if(max_energy==0)reason<=2;
     else if(max_energy<2000)reason<=3;
     else reason<=8;
    end
    if(ui_state==5)reason<=0;
    if(ui_state==0 && old_ui!=0)tracking<=0;
   end
  end
 end
endmodule
