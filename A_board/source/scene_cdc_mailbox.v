`timescale 1ns/1ps
// One held message per toggle exchange. Assert reset at both endpoints
// together; release it in each local domain.
module scene_cdc_mailbox #(parameter WIDTH=32)(
 input wire sclk,srst_n,svalid,input wire [WIDTH-1:0] sdata,
 output wire sready,output reg sdone,
 input wire dclk,drst_n,output reg dvalid,output reg [WIDTH-1:0] ddata,
 input wire dready
);
 reg request,ack;
 reg [WIDTH-1:0] held;
 (* ASYNC_REG="TRUE" *) reg ack1,ack2,req1,req2;
 reg seen_ack,seen_request;
 assign sready=request==ack2;
 always @(posedge sclk or negedge srst_n)begin
  if(!srst_n)begin request<=0;held<=0;ack1<=0;ack2<=0;seen_ack<=0;sdone<=0;end
  else begin
   ack1<=ack;ack2<=ack1;sdone<=0;
   if(svalid && sready)begin held<=sdata;request<=~request;end
   if(ack2!=seen_ack)begin seen_ack<=ack2;sdone<=1;end
  end
 end
 always @(posedge dclk or negedge drst_n)begin
  if(!drst_n)begin ack<=0;req1<=0;req2<=0;seen_request<=0;dvalid<=0;ddata<=0;end
  else begin
   req1<=request;req2<=req1;
   if(!dvalid && req2!=seen_request)begin
    ddata<=held;dvalid<=1;seen_request<=req2;
   end
   if(dvalid && dready)begin dvalid<=0;ack<=seen_request;end
  end
 end
endmodule
