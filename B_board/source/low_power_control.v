`timescale 1ns/1ps
// This control stays clocked during sleep. sleeping resets consumers before
// the four-cycle delay asserts PLL standby. Offline or ineligible cancels sleep.
module low_power_control(
 input wire clk,rst_n,online,eligible,view_valid,
 input wire [1:0] view_value,
 output reg sleeping,output wire standby
);
 reg [3:0] sleep_delay;
 assign standby=sleep_delay[3];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sleeping<=0;sleep_delay<=0;end
  else begin
   sleep_delay<={sleep_delay[2:0],sleeping};
   if(!online || !eligible) sleeping<=0;
   else if(view_valid) sleeping<=view_value==3;
  end
 end
endmodule
