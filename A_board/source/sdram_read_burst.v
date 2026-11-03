`timescale 1ns/1ps
// APUG011 uninterrupted, aligned 256-word requests; dout precedes valid.
module sdram_read_burst #(
    parameter BASE=0, WORDS=1536000, TIMEOUT=8192
)(
    input wire clk, rst, start,
    input wire [20:0] address,
    input wire mem_busy, refresh, rd_valid,
    input wire [31:0] rd_data,
    output wire busy, rd_en,
    output wire [20:0] rd_addr,
    output wire data_valid,
    output wire [31:0] data,
    output reg done, error
);
    localparam IDLE=0, ISSUE=1, DRAIN=2;
    reg [1:0] state;
    reg [20:0] base;
    reg [7:0] beat;
    reg [8:0] received;
    reg [15:0] timer;
    reg [4:0] drain;
    reg [31:0] data_d;
    always @(posedge clk) data_d<=rd_data;
    assign busy=state!=IDLE;
    assign rd_en=state==ISSUE;
    assign rd_addr=base+{13'd0,beat};
    assign data_valid=busy && rd_valid && received<256 && !error;
    assign data=data_d;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE; base<=0; beat<=0; received<=0;
            timer<=0; drain<=0; done<=0; error<=0;
        end else begin
            done<=0;
            if(state!=IDLE) begin
                timer<=timer+1'b1;
                if(rd_valid) begin
                    received<=received+1'b1;
                    if(received>=256) error<=1;
                end
            end
            case(state)
                IDLE: if(start) begin
                    base<=address; beat<=0; received<=0; timer<=0; error<=0;
                    if(address[7:0]!=0 || address<BASE ||
                       {1'b0,address}+22'd256>BASE+WORDS || mem_busy || refresh) begin
                        error<=1; done<=1;
                    end else state<=ISSUE;
                end
                ISSUE: if(beat==255) begin state<=DRAIN; drain<=16; end
                       else beat<=beat+1'b1;
                DRAIN: if(drain!=0) drain<=drain-1'b1;
                       else if(!mem_busy && !refresh && received==256) begin
                           done<=1; state<=IDLE;
                       end
                default: state<=IDLE;
            endcase
            if(state!=IDLE && timer==TIMEOUT-1) begin
                error<=1; done<=1; state<=IDLE;
            end
        end
    end
endmodule
