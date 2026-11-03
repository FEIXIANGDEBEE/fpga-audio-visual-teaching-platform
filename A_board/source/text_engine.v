`timescale 1ns/1ps
// Three registered stages: glyph index, shared 16-bit glyph row, then RGB/sync.
module text_engine #(parameter LABELS="text_a_labels.dath",FONT="v6_a_font0",FONT1="v6_a_font1",FONT2="v6_a_font2",FONT_WORDS=8192,LABEL_WORDS=4096)(
 input wire clk,rst_n,hs,vs,de,input wire [23:0] background,ink,
 input wire active,input wire [7:0] line,input wire [9:0] relx,input wire [5:0] rely,
 input wire [1:0] size,input wire override,input wire [8:0] direct_glyph,
 output reg oh,ov,od,output reg [23:0] rgb);
 // Decompose /24 as /3 on the upper seven bits plus the low three bits.
 // Preserve the saturated column and low-five-bit remainder for all 1024 inputs.
 function [9:0] cell24;input [9:0] value;
 reg [6:0] quotient;reg [1:0] remainder;reg [2:0] trial;
 reg [4:0] col24,rem24;integer bitno;
 begin
 quotient=0;remainder=0;trial=0;
 for(bitno=9;bitno>=3;bitno=bitno-1)begin
  trial={remainder,value[bitno]};
  if(trial>=3'd3)begin remainder=trial-3'd3;quotient[bitno-3]=1'b1;end
  else remainder=trial[1:0];
 end
 col24=value[9:8]==2'b11 ? 5'd31:quotient[4:0];
 rem24=value[9:8]==2'b11 ? value[4:0]-5'd8:{remainder,value[2:0]};
 cell24={col24,rem24};
 end endfunction
 function [3:0] scale24;input [4:0] value;begin
 case(value)
 5'd0:scale24=4'd0;
 5'd1:scale24=4'd0;
 5'd2:scale24=4'd1;
 5'd3:scale24=4'd2;
 5'd4:scale24=4'd2;
 5'd5:scale24=4'd3;
 5'd6:scale24=4'd4;
 5'd7:scale24=4'd4;
 5'd8:scale24=4'd5;
 5'd9:scale24=4'd6;
 5'd10:scale24=4'd6;
 5'd11:scale24=4'd7;
 5'd12:scale24=4'd8;
 5'd13:scale24=4'd8;
 5'd14:scale24=4'd9;
 5'd15:scale24=4'd10;
 5'd16:scale24=4'd10;
 5'd17:scale24=4'd11;
 5'd18:scale24=4'd12;
 5'd19:scale24=4'd12;
 5'd20:scale24=4'd13;
 5'd21:scale24=4'd14;
 5'd22:scale24=4'd14;
 5'd23:scale24=4'd15;
 default:scale24=4'd0;
 endcase
 end endfunction
 wire [9:0] cc=cell24(relx);reg [4:0] col;reg [3:0] gx,gy;
 always @*begin
  col=cc[9:5];gx=scale24(cc[4:0]);gy=scale24(rely[4:0]);
  case(size)
   0:begin col=relx[8:4];gx=relx[3:0];gy=rely[3:0];end
   2:begin col=relx[9:5];gx=relx[4:1];gy=rely[4:1];end
   default:begin end
  endcase
 end
 wire [8:0] tile1,glyph1;reg override1;reg [8:0] direct1;
 reg [3:0] gx1,gy1,gx2;wire [15:0] row2;
 reg h1,v1,d1,a1,h2,v2,d2,a2;reg [23:0] bg1,bg2,ink1,ink2;
 wire [12:0] font_address={glyph1,gy1};
 assign glyph1=override1 ? direct1:tile1;
 glyph_rom #(.WIDTH(9),.AW(12),.DEPTH(4096),.FILE(LABELS)) label_rom(clk,{line[6:0],col},tile1);
 small_font #(.ROLE(0)) small_font(clk,a1 && d1,font_address,row2);
 always @(posedge clk)begin
  override1<=override;direct1<=direct_glyph;gx1<=gx;gy1<=gy;gx2<=gx1;
  h1<=hs;v1<=vs;d1<=de;a1<=active && (override || size!=0 || relx<512);bg1<=background;ink1<=ink;
  h2<=h1;v2<=v1;d2<=d1;a2<=a1;bg2<=bg1;ink2<=ink1;
  oh<=h2;ov<=v2;od<=d2;rgb<=!d2 ? 24'd0:a2 && row2[15-gx2] ? ink2:bg2;
  if(!rst_n)begin d1<=0;d2<=0;a1<=0;a2<=0;od<=0;rgb<=0;end
 end
endmodule

module glyph_rom #(parameter WIDTH=8,AW=13,DEPTH=8192,FILE="NONE")(
 input wire clk,input wire [AW-1:0] address,output wire [WIDTH-1:0] q);
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(WIDTH),.DATA_WIDTH_B(WIDTH),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
 .DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE(FILE)) memory(
 .doa(q),.dob(),.dia({WIDTH{1'b0}}),.dib({WIDTH{1'b0}}),.cea(1'b1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
 .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address),.addrb({AW{1'b0}}));
endmodule

// Native read plus bank-select register sets the read latency. Pad only
// the last partial bank; return zero for absent banks.
