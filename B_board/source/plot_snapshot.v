`timescale 1ns/1ps
// Toggle handshake holds the bundled word until capture. Bits [2:0] are
// {zero,bank}; held_data[1:0] also reserves the source RAM bank.
module plot_snapshot(
 input wire src_clk,src_reset_n,input wire [162:0] src_data,
 input wire dst_clk,dst_reset_n,request_tick,
 output reg [162:0] snapshot,output wire [1:0] locked_bank
);
 reg request_toggle,ack_toggle,ack_seen;
 (* ASYNC_REG="TRUE" *) reg [1:0] request_sync,ack_sync;
 reg [162:0] held_data;
 assign locked_bank=held_data[1:0];
 always @(posedge src_clk or negedge src_reset_n)begin
  if(!src_reset_n)begin request_sync<=0;ack_toggle<=0;held_data<=163'd6;end
  else begin
   request_sync<={request_sync[0],request_toggle};
   if(request_sync[1]!=ack_toggle)begin held_data<=src_data;ack_toggle<=request_sync[1];end
  end
 end
 always @(posedge dst_clk or negedge dst_reset_n)begin
  if(!dst_reset_n)begin request_toggle<=0;ack_sync<=0;ack_seen<=0;snapshot<=163'd6;end
  else begin
   ack_sync<={ack_sync[0],ack_toggle};
   if(request_tick && request_toggle==ack_sync[1])request_toggle<=~request_toggle;
   if(ack_sync[1]!=ack_seen)begin snapshot<=held_data;ack_seen<=ack_sync[1];end
  end
 end
endmodule
