`timescale 1ns/1ps
`include "ui_protocol.vh"
module b_controls #(parameter HINT_CYCLES=75000000)(
 input wire clk,rst_n,input wire [3:0] short_key,long_key,sw,
 input wire [7:0] command,input wire command_valid,
 input wire [3:0] page,input wire music_valid,busy,window_active,
 input wire voice_ok,input wire [1:0] voice_command,
 output reg page_request,output reg [3:0] requested_page,output reg replay,
 output reg user_pause,right,voice_mute,voice_arm,voice_cancel,clear_peak,
 output wire mute,request_mic,hold_plot,wave_page,
 output reg [31:0] generation,output reg [3:0] hint,output reg demo_prepare,input wire ui_activity,volume_rejected,input wire ui_valid,input wire [7:0] ui_op,ui_value,input wire demo_snapshot,demo_restore,output reg history_view);
 reg mic_diag,hold_diag,wave_diag;reg mic_old;reg [26:0] hint_age;
 reg [6:0] demo_saved;
 wire uart_action=command_valid && !(|short_key) && !(|long_key);
 wire [3:0] raw_sk=short_key | {uart_action && command=="v",uart_action && command=="p",uart_action && command=="n",uart_action && command=="b"};
 wire [3:0] raw_lk=long_key | {uart_action && command=="x",uart_action && command=="c",uart_action && command=="r",uart_action && command=="z"};
 reg [3:0] sk,lk;
 // After volume routing: accept one key action. Prepare has priority
 always @*begin
  sk=0;lk=0;
  if(raw_lk[0])lk=1;
  else if(raw_sk[0])sk=1;
  else if(raw_sk[1])sk=2;
  else if(direct)begin end
  else if(raw_lk[1])lk=2;
  else if(raw_sk[2])sk=4;
  else if(raw_lk[2])lk=4;
  else if(raw_sk[3])sk=8;
  else if(raw_lk[3])lk=8;
 end
 assign request_mic=sw[2] || mic_diag;
 assign hold_plot=sw[1] || hold_diag;
 assign wave_page=sw[0] || wave_diag;
 assign mute=sw[3] || voice_mute || window_active;
 wire direct=uart_action && command>="0" && command<="9";
 wire hold_action=uart_action && (command=="h" || command=="H");
 wire manual_action=ui_valid || hold_action || ui_activity || (|sk) || (|lk) || direct || request_mic!=mic_old;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   page_request<=0;requested_page<=0;replay<=0;user_pause<=0;right<=0;voice_mute<=0;voice_arm<=0;voice_cancel<=0;clear_peak<=0;
    history_view<=0;generation<=0;hint<=0;hint_age<=0;mic_diag<=0;hold_diag<=0;wave_diag<=0;mic_old<=0;demo_prepare<=0;demo_saved<=0;
  end else begin
    page_request<=0;replay<=0;voice_arm<=0;voice_cancel<=0;clear_peak<=0;demo_prepare<=0;mic_old<=request_mic;
   if(hint_age!=0)hint_age<=hint_age-1'b1;else hint<=0;
   if(command_valid)case(command)
    "m":mic_diag<=1;"j":mic_diag<=0;"h":hold_diag<=1;"H":hold_diag<=0;
   endcase
   if(volume_rejected)begin hint_age<=HINT_CYCLES;hint<=request_mic ? 6:busy ? 1:window_active ? 9:4;end
   if(manual_action)begin generation<=generation+1'b1;voice_cancel<=1;end
    // Keep user_pause as intent; top adds the MIC/window inhibits
    if(request_mic!=mic_old)begin hint_age<=HINT_CYCLES;hint<=request_mic ? 4'd13:user_pause ? 4'd12:4'd11;end
    if(sk[0] || sk[1] || direct)begin
     hint_age<=HINT_CYCLES;
    if(busy)hint<=1;
    else if((sk[0] && page==0) || (sk[1] && page==9))hint<=2;
    else begin
      page_request<=1;requested_page<=direct ? command-8'd48:sk[0] ? page-1'b1:page+1'b1;hint<=3;
    end
   end
    else if(lk[1])begin hint_age<=HINT_CYCLES;if(busy)hint<=1;else if(!music_valid)hint<=4;else begin replay<=1;hint<=5;end end
    if(sk[2])begin hint_age<=HINT_CYCLES;if(request_mic)hint<=6;else if(!music_valid)hint<=4;else begin user_pause<=!user_pause;hint<=7;end end
    if(lk[2])begin hint_age<=HINT_CYCLES;if(request_mic)hint<=6;else begin right<=!right;hint<=8;end end
   if(sk[3])begin
     generation<=generation+1'b1;hint_age<=HINT_CYCLES;
    if(window_active)voice_cancel<=1;
    else if(busy)hint<=1;
    else begin voice_arm<=1;hint<=9;end
   end
   if(lk[3])begin voice_cancel<=1;if(!window_active)clear_peak<=1;end
   if(voice_ok && !manual_action)case(voice_command)
    1:if(!busy && page<9)begin page_request<=1;requested_page<=page+1'b1;end
    2:voice_mute<=1;
    3:voice_mute<=0;
   endcase
    if(ui_valid)begin
    case(ui_op)
     `UI_PAUSE:user_pause<=ui_value[0];
     `UI_MUTE:voice_mute<=ui_value[0];
     `UI_PAGE:begin page_request<=1;requested_page<=ui_value[3:0];end
     `UI_REPLAY:replay<=1;
     `UI_HOLD:hold_diag<=ui_value[0];
     `UI_MIC:mic_diag<=ui_value[0];
     `UI_RIGHT:right<=ui_value[0];
     `UI_WAVE:wave_diag<=ui_value[0];
     `UI_VIEW:if(ui_value<3)begin wave_diag<=ui_value==2;if(ui_value!=2)history_view<=ui_value==1;end
     `UI_ARM:voice_arm<=1;
     `UI_CANCEL:voice_cancel<=1;
     `UI_CLEAR:clear_peak<=1;
     `UI_DEMO:begin end
    endcase
   end
   // Prepare overrides keys and any late voice result on this edge
    if(lk[0])begin
     demo_prepare<=1;page_request<=1;requested_page<=0;replay<=0;
     history_view<=0;user_pause<=0;right<=0;voice_mute<=0;mic_diag<=0;hold_diag<=0;wave_diag<=0;
     voice_arm<=0;voice_cancel<=1;clear_peak<=1;hint<=10;hint_age<=HINT_CYCLES;
    end
   if(demo_snapshot)demo_saved<={history_view,user_pause,right,voice_mute,mic_diag,hold_diag,wave_diag};
   if(demo_restore){history_view,user_pause,right,voice_mute,mic_diag,hold_diag,wave_diag}<=demo_saved;
  end
 end
endmodule
