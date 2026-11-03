`timescale 1ns/1ps
// Read autoflow elapsed for the UI. No page requests here
module auto_status_view #(parameter integer SECOND_CYCLES=50000000)(
 input wire clk,rst_n,enable,running,input wire [29:0] elapsed,
 input wire fault,menu,voice,mic,pause,held,loading,ready,
 output reg [3:0] seconds,output reg [3:0] reason);
 reg [29:0] threshold,previous_elapsed;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin seconds<=15;threshold<=SECOND_CYCLES;previous_elapsed<=0;reason<=0;end
  else begin
   previous_elapsed<=elapsed;
   if(!running || elapsed<previous_elapsed)begin seconds<=15;threshold<=SECOND_CYCLES;end
   else if(elapsed>=threshold && seconds>1)begin seconds<=seconds-1'b1;threshold<=threshold+SECOND_CYCLES;end
   if(!enable)reason<=0;
   else if(fault)reason<=9;
   else if(menu)reason<=2;
   else if(voice)reason<=3;
   else if(mic)reason<=4;
   else if(pause)reason<=5;
   else if(held)reason<=6;
   else if(loading)reason<=7;
   else if(!ready || !running)reason<=8;
   else reason<=1;
  end
 end
endmodule
