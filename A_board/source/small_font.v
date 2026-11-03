`timescale 1ns/1ps
// Gate unused font-bank reads with clock enable; keep the native read latency.
module small_font #(parameter ROLE=0)(input wire clk,enable,input wire [12:0] address,output wire [15:0] q);
 wire [47:0] rows;reg [1:0] selected;
 always @(posedge clk)if(enable)selected<=address[12:11];
 assign q=selected<3 ? rows[{selected,4'd0}+:16]:16'd0;
 generate if(ROLE==0)begin:role0_bank0
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("font_a_small0.dath")) memory(
 .doa(rows[0+:16]),.dob(),.dia(16'd0),.dib(16'd0),.cea(enable && address[12:11]==0),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address[10:0]),.addrb(11'd0));
 end endgenerate
 generate if(ROLE==0)begin:role0_bank1
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("font_a_small1.dath")) memory(
 .doa(rows[16+:16]),.dob(),.dia(16'd0),.dib(16'd0),.cea(enable && address[12:11]==1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address[10:0]),.addrb(11'd0));
 end endgenerate
 generate if(ROLE==0)begin:role0_bank2
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
 .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE("font_a_small2.dath")) memory(
 .doa(rows[32+:16]),.dob(),.dia(16'd0),.dib(16'd0),.cea(enable && address[12:11]==2),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address[8:0]),.addrb(9'd0));
 end endgenerate
 generate if(ROLE==1)begin:role1_bank0
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("font_b_small0.dath")) memory(
 .doa(rows[0+:16]),.dob(),.dia(16'd0),.dib(16'd0),.cea(enable && address[12:11]==0),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address[10:0]),.addrb(11'd0));
 end endgenerate
 generate if(ROLE==1)begin:role1_bank1
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
 .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),.INIT_FILE("font_b_small1.dath")) memory(
 .doa(rows[16+:16]),.dob(),.dia(16'd0),.dib(16'd0),.cea(enable && address[12:11]==1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address[10:0]),.addrb(11'd0));
 end endgenerate
 generate if(ROLE==1)begin:role1_bank2
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
 .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE("font_b_small2.dath")) memory(
 .doa(rows[32+:16]),.dob(),.dia(16'd0),.dib(16'd0),.cea(enable && address[12:11]==2),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address[8:0]),.addrb(9'd0));
 end endgenerate
endmodule
