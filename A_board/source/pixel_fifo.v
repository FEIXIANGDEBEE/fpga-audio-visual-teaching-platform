`timescale 1ns/1ps
// Gray pointers, dual-clock RAM and a registered first-word preview.
module pixel_fifo #(parameter AW=12)(
    input wire wclk, wrst_n, wflush, push,
    input wire [31:0] wdata,
    output wire full,
    output wire [AW:0] wcount,
    input wire rclk, rrst_n, rflush, pop,
    output reg [31:0] rdata,
    output wire empty,
    output wire [AW:0] rcount
);
    reg [31:0] ram [0:(1<<AW)-1];
    reg [AW:0] wb, wg, rb, rg;
    (* ASYNC_REG="TRUE" *) reg [AW:0] rg1,rg2,wg1,wg2;
    function [AW:0] ungray;
        input [AW:0] g; integer i;
        begin ungray[AW]=g[AW];
            for(i=AW-1;i>=0;i=i-1) ungray[i]=ungray[i+1]^g[i];
        end
    endfunction
    wire [AW:0] wn=wb+(push && !full);
    wire [AW:0] rn=rb+(pop && !empty);
    assign full=wg=={~rg2[AW:AW-1],rg2[AW-2:0]};
    assign empty=rg==wg2;
    assign wcount=wb-ungray(rg2);
    assign rcount=ungray(wg2)-rb;
    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n || wflush) begin wb<=0; wg<=0; rg1<=0; rg2<=0; end
        else begin
            rg1<=rg; rg2<=rg1; wb<=wn; wg<=(wn>>1)^wn;
            if(push && !full) ram[wb[AW-1:0]]<=wdata;
        end
    end
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n || rflush) begin rb<=0; rg<=0; wg1<=0; wg2<=0; end
        else begin wg1<=wg; wg2<=wg1; rb<=rn; rg<=(rn>>1)^rn; end
    end
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n || rflush) rdata<=0;
        else rdata<=ram[rn[AW-1:0]];
    end
endmodule
