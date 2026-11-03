`timescale 1ns/1ps

module demo_control(input wire clk,rst_n,online,fault,accepted,input wire [7:0] value,
 input wire [3:0] page,output reg active,paused,output reg [1:0] interval,
 output reg snapshot,restore,page_request,output reg [3:0] target);
// accepted comes from the reliable UI link after top-level key/fault checks.
// Session loss drops the demo without restoring its saved settings.
 reg [3:0] original_page;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;paused<=0;interval<=2;original_page<=0;snapshot<=0;restore<=0;page_request<=0;target<=0;end
  else begin
   snapshot<=0;restore<=0;page_request<=0;
   if(!online || fault)begin active<=0;paused<=0;end
   else if(accepted)begin
    if(!active && value>=1 && value<=4)begin
     active<=1;paused<=0;interval<=value-1'b1;original_page<=page;snapshot<=1;
     if(page!=0)begin page_request<=1;target<=0;end
    end else if(active && value==5)paused<=!paused;
    else if(active && (value==6 || value==7))begin
     active<=0;paused<=0;restore<=1;target<=value==6 ? 0:original_page;
     if(page!=(value==6 ? 0:original_page))page_request<=1;
    end
   end
  end
 end
endmodule
