`timescale 1ns/1ps
module catalog_progress(input wire [13:0] completed,output reg [3:0] count);
 integer i;
 always @*begin count=0;for(i=0;i<14;i=i+1)count=count+completed[i];end
endmodule
