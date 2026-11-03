`timescale 1ns/1ps

module b_text #(parameter LABELS="text_a_labels.dath",FONT="v6_a_font0",FONT1="v6_a_font1",FONT2="v6_a_font2",FONT_WORDS=8192,LABEL_WORDS=4096)(
 input wire clk,rst_n,hs,vs,de,input wire [23:0] background,ink,
 input wire active,input wire [7:0] line,input wire [9:0] relx,input wire [5:0] rely,
 input wire [1:0] size,input wire override,input wire [8:0] direct_glyph,
 output reg oh,ov,od,output reg [23:0] rgb);
 // All B labels use 16px cells; keep size for the existing interface
 wire [4:0] col=relx[8:4];
 wire [3:0] gx=relx[3:0],gy=rely[3:0];
 wire [8:0] tile1,glyph1;reg override1;reg [8:0] direct1;
 reg [3:0] gx1,gy1,gx2;wire [15:0] row2;
// Three stages, including the output: index -> 16-bit glyph row -> RGB/sync
 reg h1,v1,d1,a1,h2,v2,d2,a2;reg [23:0] bg1,bg2,ink1,ink2;
 wire [12:0] font_address={glyph1,gy1};
 assign glyph1=override1 ? direct1:tile1;
 b_text_rom #(.WIDTH(9),.AW(12),.DEPTH(4096),.FILE(LABELS)) label_rom(clk,{line[6:0],col},tile1);
// small_font keeps the native read plus bank-select latency. Only the tail
// bank needs padding; an absent bank returns zero.
 small_font #(.ROLE(1)) small_font(clk,a1 && d1,font_address,row2);
 always @(posedge clk)begin
  override1<=override;direct1<=direct_glyph;gx1<=gx;gy1<=gy;gx2<=gx1;
  h1<=hs;v1<=vs;d1<=de;a1<=active && rely<16 && (override || relx<512);bg1<=background;ink1<=ink;
  h2<=h1;v2<=v1;d2<=d1;a2<=a1;bg2<=bg1;ink2<=ink1;
  oh<=h2;ov<=v2;od<=d2;rgb<=!d2 ? 24'd0:a2 && row2[15-gx2] ? ink2:bg2;
  if(!rst_n)begin d1<=0;d2<=0;a1<=0;a2<=0;od<=0;rgb<=0;end
 end
endmodule

module b_text_rom #(parameter WIDTH=8,AW=13,DEPTH=8192,FILE="NONE")(
 input wire clk,input wire [AW-1:0] address,output wire [WIDTH-1:0] q);
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(WIDTH),.DATA_WIDTH_B(WIDTH),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
 .DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE(FILE)) memory(
 .doa(q),.dob(),.dia({WIDTH{1'b0}}),.dib({WIDTH{1'b0}}),.cea(1'b1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address),.addrb({AW{1'b0}}));
endmodule


