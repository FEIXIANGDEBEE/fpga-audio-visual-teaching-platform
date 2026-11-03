`timescale 1ns/1ps
// Bundled-data mailbox: source holds the entire word until the next request.
// The destination samples after the acknowledgement crosses two flip-flops.
module cdc_snapshot #(parameter WIDTH=144)(
 input wire src_clk, input wire src_reset_n, input wire [WIDTH-1:0] src_data,
 input wire dst_clk, input wire dst_reset_n, input wire request_tick,
 output reg [WIDTH-1:0] snapshot
);
 reg request_toggle, ack_toggle, ack_seen;
 (* ASYNC_REG="TRUE" *) reg [1:0] request_sync, ack_sync;
 reg [WIDTH-1:0] held_data;
 always @(posedge src_clk or negedge src_reset_n) begin
   if(!src_reset_n) begin request_sync<=0; ack_toggle<=0; held_data<=0; end
   else begin
     request_sync<={request_sync[0],request_toggle};
     if(request_sync[1]!=ack_toggle) begin
       held_data<=src_data; ack_toggle<=request_sync[1];
     end
   end
 end
 always @(posedge dst_clk or negedge dst_reset_n) begin
   if(!dst_reset_n) begin request_toggle<=0; ack_sync<=0; ack_seen<=0; snapshot<=0; end
   else begin
     ack_sync<={ack_sync[0],ack_toggle};
     if(request_tick && request_toggle==ack_sync[1]) request_toggle<=~request_toggle;
     if(ack_sync[1]!=ack_seen) begin snapshot<=held_data; ack_seen<=ack_sync[1]; end
   end
 end
endmodule
