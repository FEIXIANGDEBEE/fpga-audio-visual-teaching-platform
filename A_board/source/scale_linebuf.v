`timescale 1ns/1ps
// Two row banks let fill prepare the next source row while emit reads the
// current row. The scaler assigns ownership from row IDs versus need_sy.
// Hold read data during stalls with clock enable. The production 2048x24
// shape uses native BRAM; other parameter values use separate inferred banks.
module scale_linebuf #(
    parameter integer AW = 11,        // 2048 pixels deep (max source width)
    parameter integer DW = 24         // RGB888
)(
    input               clk,

    // write port (fill side)
    input               wr_en,
    input               wr_sel,       // 0 -> bank0, 1 -> bank1
    input  [AW-1:0]     wr_addr,
    input  [DW-1:0]     wr_data,

    // read port (emit side)
    input               rd_en,        // enabled read: data must hold on stall
    input               rd_sel,       // 0 -> bank0, 1 -> bank1
    input  [AW-1:0]     rd_addr,
    output [DW-1:0]     rd_data
);

// Pack both 2048x24 banks into three 32K byte lanes. Read CE holds data on stalls.
generate if (AW==11 && DW==24) begin:g_lane32
    genvar lane;
    for(lane=0;lane<3;lane=lane+1)begin:g_lane
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),
          .DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
          .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K")) lane_ram(
          .doa(),.dob(rd_data[lane*8 +:8]),.dia(wr_data[lane*8 +:8]),.dib(8'd0),
          .cea(wr_en),.ceb(rd_en),.ocea(1'b1),.oceb(1'b1),.clka(clk),.clkb(clk),
          .wea(wr_en),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
          .addra({wr_sel,wr_addr}),.addrb({rd_sel,rd_addr}));
    end
end else begin:g_generic
localparam integer N = 1 << AW;

(* ram_style = "bram" *) reg [DW-1:0] bank0 [0:N-1];
(* ram_style = "bram" *) reg [DW-1:0] bank1 [0:N-1];

// Keep generic-bank reads separate, then mux their registered outputs.
// Putting the selection inside the array read prevents this intended RAM mapping.
reg [DW-1:0] q0, q1;
reg          sel_d;

always @(posedge clk) begin
    if (wr_en && !wr_sel) bank0[wr_addr] <= wr_data;
end
always @(posedge clk) begin
    if (wr_en &&  wr_sel) bank1[wr_addr] <= wr_data;
end

// Read latency is one cycle. rd_en also holds the bank selector,
// so data remains fixed during out_ready backpressure.
always @(posedge clk) begin
    if (rd_en) begin
        q0 <= bank0[rd_addr];
        q1 <= bank1[rd_addr];
    end
end
always @(posedge clk) begin
    if (rd_en) sel_d <= rd_sel;
end

assign rd_data = sel_d ? q1 : q0;

end endgenerate
endmodule
