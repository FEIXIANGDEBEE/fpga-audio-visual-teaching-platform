`timescale 1ns/1ps
module spectrogram(
 input wire clk,rst_n,wr_start,write_en,clear,
 input wire [127:0] heights,
 input wire [9:0] x,y,
 input wire show,
 output wire [23:0] rgb,
 output wire in_area,output wire [8:0] history_filled
);
 reg [8:0] wr_ptr;reg [3:0] wr_idx;reg wr_busy;reg [8:0] filled;
 wire [12:0] wa={wr_ptr,wr_idx};
 wire [7:0]  wd=heights[wr_idx*8 +: 8];
 wire we=wr_busy && rst_n && !clear;

 function [3:0] band_of;input [9:0] yb;begin
  if(yb<12)band_of=4'd15;else if(yb<24)band_of=4'd14;else if(yb<36)band_of=4'd13;
  else if(yb<48)band_of=4'd12;else if(yb<60)band_of=4'd11;else if(yb<72)band_of=4'd10;
  else if(yb<84)band_of=4'd9;else if(yb<96)band_of=4'd8;else if(yb<108)band_of=4'd7;
  else if(yb<120)band_of=4'd6;else if(yb<132)band_of=4'd5;else if(yb<144)band_of=4'd4;
  else if(yb<156)band_of=4'd3;else if(yb<168)band_of=4'd2;else if(yb<180)band_of=4'd1;
  else band_of=4'd0;
 end endfunction

 wire [9:0] xa=x+10'd2;
 wire [8:0] c_raw=(xa<10'd32)?9'd0:((xa-10'd32)>>1);
 wire [8:0] cc=(c_raw>9'd287)?9'd287:c_raw;
 wire [8:0] col=(wr_ptr+cc-9'd288)&9'h1FF;
 wire [9:0] yb=y-10'd160;
 wire [3:0] band=band_of(yb);
 wire [12:0] ra=(y>=10'd160&&y<10'd352)?{col,band}:13'd0;

 wire [7:0] hist_q;wire [23:0] pal_q;

 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(13),.ADDR_WIDTH_B(13),
  .DATA_DEPTH_A(8192),.DATA_DEPTH_B(8192),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"))
  hist(.doa(hist_q),.dob(),.dia(8'd0),.dib(wd),.cea(1'b1),.ceb(we),.ocea(1'b1),.oceb(1'b0),
  .clka(clk),.clkb(clk),.wea(1'b0),.web(we),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
  .addra(ra),.addrb(wa));

 EG_LOGIC_BRAM #(.DATA_WIDTH_A(24),.DATA_WIDTH_B(24),.ADDR_WIDTH_A(8),.ADDR_WIDTH_B(8),
  .DATA_DEPTH_A(256),.DATA_DEPTH_B(256),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),
  .INIT_FILE("spectrum_palette.dath"))
  pal(.doa(pal_q),.dob(),.dia(24'd0),.dib(24'd0),.cea(1'b1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
  .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
  .addra(hist_q),.addrb(8'd0));

 wire [8:0] c_disp=(x<10'd32)?9'd0:((x-10'd32)>>1);
 wire [9:0] age=10'd287-{1'b0,c_disp};
 wire blank=(age>={1'b0,filled});
 assign history_filled=filled;
 // A separator dims each channel to 3/4; it never replaces energy.
 wire separator=(y==160 || y==172 || y==184 || y==196 || y==208 || y==220 || y==232 || y==244 || y==256 || y==268 || y==280 || y==292 || y==304 || y==316 || y==328 || y==340);
 wire [7:0] dim_r={1'b0,pal_q[23:17]}+{2'b0,pal_q[23:18]};
 wire [7:0] dim_g={1'b0,pal_q[15:9]}+{2'b0,pal_q[15:10]};
 wire [7:0] dim_b={1'b0,pal_q[7:1]}+{2'b0,pal_q[7:2]};
 assign rgb=blank ? 24'h0a1119:separator ? {dim_r,dim_g,dim_b}:pal_q;
 assign in_area=show && x>=10'd32 && x<10'd608 && y>=10'd160 && y<10'd352 && rst_n;

 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin wr_busy<=0;wr_idx<=0;wr_ptr<=0;filled<=0;end
  else if(clear)begin wr_busy<=0;wr_idx<=0;wr_ptr<=0;filled<=0;end
  else if(wr_start&&write_en&&!wr_busy)begin wr_busy<=1;wr_idx<=0;end
  else if(wr_busy)begin
    if(wr_idx==4'd15)begin wr_busy<=0;wr_ptr<=wr_ptr+1'b1;if(filled<9'd288)filled<=filled+1'b1;end
    else wr_idx<=wr_idx+1'b1;
  end
endmodule
