`timescale 1ns/1ps
// Convert six decimal values on one 16-step double-dabble unit. Publish
// them together only if the qualified geometry still matches.
module geometry_display(
 input wire clk,rst_n,valid,input wire [69:0] geometry,
 output reg [95:0] decimals,output wire ready
);
 reg [69:0] held,published_geometry;reg running,published_valid;
 reg [2:0] field;reg [4:0] step;reg [15:0] binary,bcd;
 reg [95:0] working;reg [15:0] adjusted;integer i;
 assign ready=valid && published_valid && published_geometry==geometry;
 function [15:0] value;
  input [69:0] g;input [2:0] f;
  begin case(f)
   0:value=g[69:54];1:value=g[53:38];2:value={6'd0,g[37:28]};
   3:value={7'd0,g[27:19]};4:value={6'd0,g[18:9]};default:value={7'd0,g[8:0]};
  endcase end
 endfunction
 always @*begin
  adjusted=bcd;
  for(i=0;i<4;i=i+1)if(bcd[i*4+:4]>=5)adjusted[i*4+:4]=bcd[i*4+:4]+4'd3;
 end
 wire [15:0] next_bcd={adjusted[14:0],binary[15]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   held<=0;published_geometry<=0;running<=0;published_valid<=0;field<=0;step<=0;binary<=0;bcd<=0;working<=0;decimals<=0;
  end else if(!valid)begin running<=0;published_valid<=0;end
  else if(!running && !ready)begin
   held<=geometry;running<=1;field<=0;step<=0;binary<=value(geometry,0);bcd<=0;
  end else if(running)begin
   if(geometry!=held)running<=0;
   else begin
    binary<={binary[14:0],1'b0};bcd<=next_bcd;step<=step+1'b1;
    if(step==15)begin
     working[field*16+:16]<=next_bcd;
     if(field==5)begin decimals<={next_bcd,working[79:0]};published_geometry<=held;published_valid<=1;running<=0;end
     else begin field<=field+1'b1;step<=0;binary<=value(held,field+1'b1);bcd<=0;end
    end
   end
  end
 end
endmodule
