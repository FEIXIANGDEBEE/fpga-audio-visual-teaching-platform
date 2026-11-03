`timescale 1ns/1ps
`include "text_a_defs.vh"
module a_osd(input wire clk,rst_n,hs,vs,de,input wire [9:0] x,y,input wire [23:0] rgb,
 input wire [2:0] menu,input wire notice,input wire [1:0] notice_kind,
 input wire [3:0] switches,page,input wire [1:0] effect,input wire [2:0] brightness,contrast,
 input wire [13:0] end_record,input wire [12:0] filter_record,input wire [7:0] auto_status,
 input wire freeze,hide,fault,output wire oh,ov,od,output wire [23:0] out_rgb,output wire [63:0] scroll_stats,input wire [111:0] display_record,input wire [127:0] ui_view,
 input wire [5:0] meter_end);
 // Both inputs stay fixed through vertical blank. Two 11-cycle BCD jobs
 // finish over 35000 clocks before the next active pixel.
 reg [15:0] end_bcd,number_work;reg [7:0] filter_bcd;
 reg [10:0] number_shift;reg [5:0] filter_latched;reg [3:0] number_left;reg number_filter;
 wire [15:0] number_adjusted;
 genvar digit_index;
 generate for(digit_index=0;digit_index<4;digit_index=digit_index+1)begin:g_bcd_adjust
  assign number_adjusted[digit_index*4+:4]=number_work[digit_index*4+:4]>=5 ? number_work[digit_index*4+:4]+4'd3:number_work[digit_index*4+:4];
 end endgenerate
 wire [15:0] number_next={number_adjusted[14:0],number_shift[10]};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin end_bcd<=0;filter_bcd<=0;number_work<=0;number_shift<=0;filter_latched<=0;number_left<=0;number_filter<=0;end
  else if(x==0 && y==481)begin number_shift<=end_record[10:0];filter_latched<=filter_record[9:4];number_work<=0;number_left<=11;number_filter<=0;end
  else if(number_left!=0)begin
   number_work<=number_next;number_shift<={number_shift[9:0],1'b0};number_left<=number_left-1'b1;
   if(number_left==1)begin
    if(!number_filter)begin end_bcd<=number_next;number_work<=0;number_shift<={5'd0,filter_latched};number_left<=11;number_filter<=1;end
    else filter_bcd<=number_next[7:0];
   end
  end
 end
 wire geometry_ready=display_record[111];wire [95:0] geometry_bcd=display_record[110:15];
 wire [3:0] visible_page=display_record[14:11],target_page=display_record[10:7];
 wire [2:0] load_phase=display_record[6:4];wire [3:0] load_segments=display_record[3:0];
 wire [4:0] char_cell=(x-24)>>4;wire [4:0] bar_cell=(x-24)>>6;
 reg [15:0] number;reg [1:0] decimal_place;
 reg [9:0] scroll;reg [5:0] dwell;reg [3:0] old_page;reg old_enable;reg [31:0] frames;
 wire [10:0] period=page==5 ? `A_SUB6_PERIOD:page==6 ? `A_SUB7_PERIOD:page==4 ? `A_SUB5_PERIOD:`A_SUB4_PERIOD;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin scroll<=0;dwell<=0;old_page<=15;old_enable<=0;frames<=0;end
  else if(x==0 && y==481)begin
   frames<=frames+1'b1;old_page<=page;old_enable<=switches[1] && !hide;
   if(page!=old_page || !switches[1] || !old_enable || hide)begin scroll<=0;dwell<=0;end
   else if(!freeze && menu==0)begin
    if(dwell<60)dwell<=dwell+1'b1;
    else if(scroll<384)begin scroll<=scroll+1'b1;if(scroll==383)dwell<=30;end
    else begin scroll<=0;dwell<=0;end
   end
  end
 end
 assign scroll_stats={frames,2'd0,contrast,brightness,page,switches[1],dwell,scroll,3'd0};
 reg active,override;reg [7:0] line;reg [9:0] xx;reg [5:0] yy;reg [1:0] size;reg [8:0] gid;
 reg [23:0] bg,ink;reg [3:0] row;reg [9:0] left,width,top;reg [10:0] pos;
 function [8:0] digit;input [3:0] n;begin digit=`A_G_0030+n;end endfunction
 wire ui_overlay,ui_active,ui_direct;wire [7:0] ui_line;wire [9:0] ui_x;wire [5:0] ui_y;wire [1:0] ui_size;wire [8:0] ui_glyph;wire [23:0] ui_bg,ui_ink;
 osd_layout layout(x,y,de,rgb,ui_view,switches,page,brightness,contrast,effect,ui_overlay,ui_active,ui_direct,ui_line,ui_x,ui_y,ui_size,ui_glyph,ui_bg,ui_ink);
 reg [2:0] bg_select;
 always @*begin
  case(bg_select)
   3'd0:bg=rgb;
   3'd1:bg=24'hf4f0e7;
   3'd2:bg=24'h2b9b8c;
   3'd3:bg=24'hd6ddd8;
   3'd4:bg=ui_bg;
   3'd5:bg=24'hfff0e7;
   3'd6:bg=24'hfdc81a;
   3'd7:bg=24'he04a3c;
  endcase
 end
 always @*begin
  number=0;decimal_place=0;active=0;override=0;line=0;xx=x-24;yy=0;size=1;gid=0;bg_select=0;ink=24'h263645;row=0;
  left=32;width=576;top=page==6 ? 400:page==5 ? 364:416;
  pos={1'b0,x}-{1'b0,left}+scroll;
  if(de && page==7 && menu==0 && x>=24 && x<616)begin
   if(y>=196 && y<228)begin
    active=1;line=`A_FILTER0;size=2;yy=y-196;
    if(x>=184 && x<248)begin override=1;gid=filter_record[12:10]!=0 ? `A_G_002D:x<216 ? digit(filter_bcd[7:4]):digit(filter_bcd[3:0]);end
   end
   if(y>=234 && y<250)begin active=1;line=`A_FILTER_STATE0+filter_record[12:10];size=0;yy=y-234;end
   if(y>=254 && y<270 && end_record[13:11]!=0)begin
    active=1;line=end_record[13:11]==3 ? `A_END0:end_record[13:11]==2 ? `A_END1:`A_END2;size=0;yy=y-254;
    if(end_record[13:11]==3 && x>=200 && x<264)begin
     override=1;
     if(x<216)gid=digit(end_bcd[15:12]);else if(x<232)gid=digit(end_bcd[11:8]);
     else if(x<248)gid=digit(end_bcd[7:4]);else gid=digit(end_bcd[3:0]);
    end
   end
   if(y>=288 && y<304 && end_record[13:11]!=0)begin active=1;line=`A_ENDSCOPE;size=0;yy=y-288;end
  end
  if(de && switches[1] && page>=3 && page<=6 && !hide && menu==0 && x>=left && x<left+width && y>=top && y<top+32)begin
   active=1;line=`A_SUB4+page-3;size=2;xx=pos[9:0];yy=y-top;ink=(ui_view[111:110]==1 || (ui_view[111:110]==0 && page==3)) ? 24'hfdc81a:24'h1b6e86;
  end
  if(de && notice && menu==0 && x>=16 && x<624 && y>=8 && y<44)begin
   bg_select=1;xx=x-24;yy=y-14;size=1;
   active=x>=24 && x<616 && y>=14 && y<38;
   line=notice_kind==0 ? `A_FX0+effect:notice_kind==1 ? `A_BR5_BASE+brightness:`A_CT5_BASE+contrast;
  end
  if(de && menu==0 && load_phase>=1 && load_phase<=5 && x>=16 && x<624 && y>=8 && y<68)begin
   bg_select=1;active=x>=24 && x<600 && y>=16 && y<32;xx=x-24;yy=y-16;size=0;override=0;
   line=`A_LOAD0+load_phase-1'b1;ink=24'h1e5a7a;
   if(load_phase>=2 && (char_cell==5 || char_cell==6))begin override=1;gid=digit(char_cell==5 ? (target_page==9 ? 1:0):(target_page==9 ? 0:target_page+1'b1));end
   if(y>=46 && y<56 && x>=24 && x<536 && ((x-24)&63)<60)begin
    active=0;bg_select=bar_cell<load_segments ? 2:3;
   end
  end
  // Draw the 12x12 meter cells below subtitles; hint, fault and menu overlays keep priority.
  if(de && menu==0 && !hide && page>=3 && page<=9 && y>=458 && y<470 && x>=64 && x[3:0]<12 && x[9:4]<meter_end)
   bg_select=x[9:4]>=30 ? 3'd7:x[9:4]>=24 ? 3'd6:3'd2;
  if(ui_overlay)begin bg_select=4;ink=ui_ink;active=ui_active;override=ui_direct;line=ui_line;xx=ui_x;yy=ui_y;size=ui_size;gid=ui_glyph;end
  if(de && fault && x>=16 && x<624 && y>=8 && y<44)begin
   bg_select=5;active=x>=24 && x<616 && y>=14 && y<38;xx=x-24;yy=y-14;size=1;line=`A_FAULT;ink=24'hb32020;override=0;
  end
 end
 text_engine #(.LABELS("text_a_labels.dath"),.FONT("v6_a_font0"),.FONT1("v6_a_font1"),.FONT2("v6_a_font2"),.FONT_WORDS(`A_FONT_WORDS),.LABEL_WORDS(`A_LABEL_WORDS))
 text_engine(clk,rst_n,hs,vs,de,bg,ink,active,line,xx,yy,size,override,gid,oh,ov,od,out_rgb);
endmodule
