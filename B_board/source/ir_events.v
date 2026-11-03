`timescale 1ns/1ps
// PRESS=1, STEP=2, ACTIVITY=4; held_valid comes from the NEC decoder.
module ir_events(input wire clk,rst_n,ms_tick,frame,repeat_frame,held_valid,key_valid,
 input wire [4:0] key,input wire blocked,output reg valid,output reg [4:0] id,output reg [2:0] flags,
 output reg [7:0] dropped);
 reg tracking;reg [4:0] tracked;reg [9:0] age;reg [7:0] step_age;reg stepped;
 wire activity=held_valid && (repeat_frame || frame && key_valid && tracking && key==tracked);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tracking<=0;tracked<=0;age<=0;step_age<=0;stepped<=0;valid<=0;id<=0;flags<=0;dropped<=0;end
  else begin
   valid<=0;
   if(!held_valid)begin tracking<=0;age<=0;step_age<=0;stepped<=0;end
   if(frame && key_valid && (!tracking || key!=tracked))begin
    tracking<=1;tracked<=key;age<=0;step_age<=0;stepped<=0;
    if(!blocked)begin valid<=1;id<=key;flags<=1;end else dropped<=dropped+1'b1;
   end else if(tracking && activity && !blocked)begin valid<=1;id<=tracked;flags<=4;end
   if(ms_tick && tracking && held_valid)begin
    if(!stepped)begin
     if(age==599)begin stepped<=1;step_age<=0;if(!blocked && tracked<4)begin valid<=1;id<=tracked;flags<=2;end end
     else age<=age+1'b1;
    end else if(step_age==199)begin step_age<=0;if(!blocked && tracked<4)begin valid<=1;id<=tracked;flags<=2;end end
    else step_age<=step_age+1'b1;
   end
   if(frame && !key_valid)begin tracking<=0;age<=0;step_age<=0;stepped<=0;valid<=0;end
  end
 end
endmodule
