`timescale 1ns/1ps
// The pixel fault stays sticky until pixel reset; synchronize that level into SYS.
module layer_fault_cdc(input wire clk,rst_n,fault_async,output wire fault);
 (* ASYNC_REG="TRUE" *) reg meta,sync;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin meta<=0;sync<=0;end
  else begin meta<=fault_async;sync<=meta;end
 assign fault=sync;
endmodule
