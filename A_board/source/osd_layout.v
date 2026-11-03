`timescale 1ns/1ps
`include "text_a_defs.vh"
module osd_layout(input wire [9:0] x,y,input wire de,input wire [23:0] rgb,input wire [127:0] view,
 input wire [3:0] switches,page,input wire [2:0] brightness,contrast,input wire [1:0] effect,
 output reg overlay,active,direct,output reg [7:0] line,output reg [9:0] xx,output reg [5:0] yy,
 output reg [1:0] size,output reg [8:0] glyph,output reg [23:0] bg,ink);
 reg [3:0] bg_select;
 always @*begin
  case(bg_select)
   4'd0:bg=rgb;
   4'd1:bg=shade;
   4'd2:bg=24'h728899;
   4'd3:bg=24'h2aafc3;
   4'd4:bg=24'h176b83;
   4'd5:bg=24'hfdc81a;
   4'd6:bg=24'h1b6e86;
   4'd7:bg=24'h9aaebb;
   4'd8:bg=24'h71818b;
   4'd9:bg=24'h36cbb5;
   4'd10:bg=24'h40515e;
   4'd11:bg=24'h182430;
   default:bg=rgb;
  endcase
 end
 wire [2:0] state=view[2:0],cat=view[5:3],item=view[8:6];wire [3:0] draft=view[12:9],hint=view[17:14];
 wire [3:0] volume=view[46:43],bsw=view[50:47];wire [7:0] play=view[58:51],analysis=view[66:59];
 wire [7:0] directory=view[82:75];
 wire [3:0] physical_switches=view[103:100];
 wire [3:0] rec_state=view[127:124];wire [4:0] rec_cells=view[123:119];
 wire [1:0] rec_result=view[118:117];wire rec_owner=view[116];
 wire rec_shortcut=view[112];
 wire rec_card=page==9 && (rec_shortcut || rec_owner || rec_result!=0 || !view[18]);
 wire [4:0] rec_cell=(x-336)>>3;
 wire [23:0] shade;
 assign shade[23:16]={1'b0,rgb[23:17]}+8'h0c;
 assign shade[15:8]={1'b0,rgb[15:9]}+8'h12;
 assign shade[7:0]={1'b0,rgb[7:1]}+8'h18;
 wire locked=cat==0 && (item==4 && |physical_switches[3:2]) || cat==1 && item==1 && bsw[3] ||
 cat==2 && item==1 && physical_switches[0] || cat==3 && (item==0 && bsw[0] || item==2 && bsw[1] || item==3 && bsw[2]);
 reg [2:0] row,logical_row;reg [7:0] value_line;reg [3:0] value_number;reg numeric;reg [3:0] count;
 wire [7:0] first_line=cat==0 ? `A_UI_I0:cat==1 ? `A_UI_I5:cat==2 ? `A_UI_I9:cat==3 ? `A_UI_I13:`A_UI_I19;
 wire [2:0] last=cat==0 || cat==3 ? 5:cat==4 ? 4:3;
 function [8:0] digit;input [3:0] v;begin digit=`A_G_0030+v;end endfunction
 always @*begin
  overlay=0;active=0;direct=0;line=0;xx=0;yy=0;size=0;glyph=0;bg_select=0;ink=24'hedf3f7;
  row=0;logical_row=0;value_line=`A_UI_ENTER;value_number=0;numeric=0;count=0;
  if(de && state!=0 && x>=88 && x<552 && y>=96 && y<384)begin
   overlay=1;
   bg_select=1;
   if(x==88 || x==551 || y==96 || y==383 || y==144 && x>=104 && x<536 || x==192 && y>=152 && y<328)bg_select=2;
   if(y>=112 && y<136 && x>=104 && x<536)begin
    active=1;size=1;yy=y-112;xx=x<384 ? x-104:x-384;line=x<384 ? `A_UI_TITLE:`A_UI_CAT0+cat;
   end
   if(x>=104 && x<192 && y>=152 && y<312)begin
    row=(y-152)>>5;
    if(cat==row)bg_select=state==1 ? 3:4;
    active=(y-152)%32<16;line=`A_UI_CAT0+row;xx=x-104;yy=(y-152)%32;size=0;
   end
   if(x>=208 && x<536 && y>=152 && y<312)begin
    row=(y-152)>>5;logical_row=row+(item==5 ? 1:0);
    if(logical_row<=last)begin
     if(logical_row==item && state!=1)bg_select=state==3 ? 4:3;
     active=(y-152)%32>=4 && (y-152)%32<28;size=1;yy=(y-152)%32-4;xx=x-216;line=first_line+logical_row;
     if(cat==0 && logical_row==5)begin
      direct=1;glyph=xx<24 ? `A_G_56FE:xx<48 ? `A_G_5C42:xx<72 ? `A_G_8FD0:xx<96 ? `A_G_52A8:`A_G_0020;
     end
     if(x<216)active=0;
     if(x>=432)begin
      size=0;yy=(y-152)%32-8;active=(y-152)%32>=8 && (y-152)%32<24;xx=x-432;
      if(cat==0)case(logical_row)
       0:begin numeric=1;value_number=brightness+1'b1;end
       1:begin numeric=1;value_number=contrast+1'b1;end
       2:value_line=`A_UI_FX0+effect;
       3:begin if(active && x<496)bg_select=(view[111:110]==1 || (view[111:110]==0 && x<464)) ? 5:6;active=0;end
       4:value_line=`A_UI_FILTER0+switches[3:2];
       5:begin direct=1;glyph=xx<16 ? (view[109:108]==0 ? `A_G_5173:view[109:108]==1 ? `A_G_5F31:`A_G_5F3A):`A_G_0020;end
      endcase
      else if(!view[99] && !(cat==2 && logical_row==2))value_line=`A_UI_UNKNOWN;
      else if(cat==1)case(logical_row)
       0:begin numeric=1;value_number=volume;end
       1:value_line=play[2] ? `A_UI_ON:`A_UI_OFF;
       2:value_line=play[0] ? `A_UI_PAUSE:`A_UI_PLAY;
      endcase
      else if(cat==2)case(logical_row)
       0:begin numeric=1;value_number=(state==3 && item==0 ? draft:page)+1'b1;end
       1:value_line=switches[0] ? `A_UI_AUTO:`A_UI_MANUAL;
       2:value_line=`A_UI_TIME;
      endcase
      else if(cat==3)case(logical_row)
       0:begin value_line=(play[7] || analysis[1]) ? `A_UI_WAVE:`A_UI_SPECTRUM;
        if(play[7])xx={1'b0,1'b1,xx[7:0]};
        if(!play[7] && !analysis[1] && analysis[7])begin direct=1;glyph=xx<16 ? 9'd87:xx<32 ? 9'd234:`A_G_0020;end end
       1:value_line=analysis[0] ? `A_UI_RIGHT:`A_UI_LEFT;
       2:value_line=analysis[2] ? `A_UI_HOLD:`A_UI_LIVE;
       3:value_line=analysis[3] ? `A_UI_MIC:`A_UI_MUSIC;
       4:value_line=analysis[4] ? `A_UI_ON:`A_UI_OFF;
      endcase
      else if(cat==4 && logical_row<3)value_line=view[42] ? `A_UI_SAVE:!view[41] ? `A_UI_WAIT:`A_UI_ENTER;
      line=value_line;
      if(numeric)begin
       direct=1;glyph=xx<16 ? digit(value_number==10 ? 1:value_number):value_number==10 && xx<32 ? digit(0):`A_G_0020;
       if(cat==0 && logical_row<2 || cat==1 && logical_row==0)begin
        if(xx>=16 && xx<32)glyph=`A_G_002F;
        if(xx>=32 && xx<48)glyph=digit(cat==0 ? 5:9);
       end
      end
      if(cat==2 && logical_row==2)begin
       direct=1;
       case(state==3 && item==2 ? draft[1:0]:view[105:104])
        0:glyph=xx<16 ? digit(5):xx<32 ? `A_G_0020:xx<48 ? `A_G_79D2:`A_G_0020;
        1:glyph=xx<16 ? digit(1):xx<32 ? digit(0):xx<48 ? `A_G_79D2:`A_G_0020;
        2:glyph=xx<16 ? digit(1):xx<32 ? digit(5):xx<48 ? `A_G_79D2:`A_G_0020;
        3:glyph=xx<16 ? digit(3):xx<32 ? digit(0):xx<48 ? `A_G_79D2:`A_G_0020;
       endcase
      end
     end
    end
    if(state==4)begin
     active=0;direct=0;size=0;xx=x-216;yy=0;
     if(y>=176 && y<192)begin active=1;yy=y-176;line=cat==4 ? (view[40] ? `A_UI_OVERWRITE:`A_UI_RECORD_NEW):`A_UI_DEMO;ink=24'hffd27a;end
     if(cat==4 && y>=208 && y<224)begin active=1;yy=y-208;line=!view[99] ? `A_UI_UNKNOWN:view[40] ? `A_UI_SLOT_PRESENT:`A_UI_SLOT_EMPTY;end
     if(y>=240 && y<256)begin active=1;yy=y-240;line=view[13] ? `A_UI_CHOICE1:`A_UI_CHOICE0;end
    end
    if(state==6 || state==7)begin active=y>=176 && y<192;direct=0;size=0;xx=x-216;yy=y-176;line=`A_UI_WAIT;end
    if(state==5)begin
     active=(y-152)%32<16;direct=0;size=0;xx=x-216;yy=(y-152)%32;
     if(item==3)begin
      case(row)
       0:line=`A_UI_INFO0;
       1:line=`A_UI_INFO1;
       2:begin line=`A_UI_INFO2;if(x>=328 && x<360)begin direct=1;glyph=x<344 ? digit(page==9 ? 1:page+1'b1):page==9 ? digit(0):`A_G_0020;end end
       3:line=!view[99] ? `A_UI_UNKNOWN:directory[6] ? `A_UI_CHECK2:directory[5] ? `A_UI_CHECK1:`A_UI_CHECK0;
       4:line=view[42] ? `A_UI_SAVE:!view[39] ? `A_UI_UNKNOWN:`A_UI_H0;
      endcase
     end else begin
      case(row)0:line=`A_UI_HELP0;1:line=`A_UI_HELP1;2:line=`A_UI_HELP2;3:line=`A_UI_HELP3;default:active=0;endcase
     end
    end
   end
   if((cat==0 || cat==3) && item==5 && x>=532 && x<535 && y>=184 && y<312)bg_select=7;
   if(state==3 && y>=320 && y<328 && x>=216 && x<528 && (cat==0 && item<2 || cat==1 && item==0))begin
    count=cat==1 ? (x-216)>>5:(x-216)>>6;
    if((cat==1 ? ((x-216)&31)<26:((x-216)&63)<52))bg_select=(cat==1 ? count<volume:count<=(item==0 ? brightness:contrast)) ? 3:8;
   end
   if(x>=104 && x<536 && y>=344 && y<376)begin
    active=1;direct=0;size=0;xx=x-104;yy=y<360 ? y-344:y-360;
    if(y<360)begin
     line=state==4 ? `A_UI_CONFIRM:state==3 ? `A_UI_EDIT:`A_UI_FOOT;
    end else begin
     ink=24'hffd27a;
     line=view[42] ? `A_UI_SAVE:locked && state!=1 ? `A_UI_H3:hint<=9 && hint!=0 ? `A_UI_H0+hint:
       !view[99] ? `A_UI_H6:!directory[5] ? `A_UI_H2:directory[6] ? `A_UI_CHECK2:cat==0 && item==3 && (page<3 || page>6) ? `A_UI_NONE:
       cat==1 && item==0 && !play[4] ? `A_UI_PRESET:`A_UI_H0;
    end
   end
  end
  // One compact card shares the menu shade and the existing text pipeline.
  if(de && state==0 && (rec_card || view[18] || view[42]) && x>=320 && x<624 && y>=16 && y<(rec_card ? 136:64))begin
   overlay=1;bg_select=1;direct=0;size=0;xx=x-336;yy=y-28;
   active=x>=336 && x<608 && y>=28 && y<44;
   if(x==320 || x==623 || y==16 || y==(rec_card ? 135:63))bg_select=2;
   line=!view[99] ? `A_UI_UNKNOWN:hint!=0 && hint<=9 && hint!=8 && !rec_owner && !rec_shortcut ? `A_UI_H0+hint:
    rec_card ? (view[42] || rec_state==4 ? `A_UI_SAVE:rec_state==9 || rec_shortcut && hint==4 ? `A_REC_FAIL:
     rec_shortcut ? `A_REC_PREPARE:rec_result==2 ? `A_REC_FAIL:rec_owner ? (rec_state==1 ? (rec_result==1 ? `A_REC_SAVED:`A_UI_RECORD_NEW):rec_state==3 ? `A_REC_CAPTURE:rec_state==6 ? `A_UI_PLAY:`A_REC_PREPARE):rec_result==1 ? `A_REC_SAVED:`A_UI_RECORD_NEW):
    view[38:37]==3 ? (view[36:35]==0 ? `A_BR5_BASE+brightness:view[36:35]==1 ? `A_CT5_BASE+contrast:view[36:35]==2 ? `A_UI_FX0+effect:`A_REC_PREPARE):
    view[38:37]==1 ? `A_UI_VOLUME:bsw[1] ? `A_UI_H3:analysis[1] ? `A_UI_WAVE:analysis[2] ? `A_UI_HOLD:`A_UI_SPECTRUM;
   if(!rec_card && view[38:37]==2 && hint==0 && !analysis[1] && analysis[7] && x>=336 && x<368)begin direct=1;glyph=x<352 ? `A_G_58F0:`A_G_8C31;end
   if(!rec_card && view[38:37]==1 && x>=400 && x<416)begin direct=1;glyph=digit(volume);end
   if(rec_card)begin
    if(view[99] && rec_owner && (rec_state==3 || rec_state==4) && x>=336 && x<528 && y>=60 && y<76)begin
     active=0;if(((x-336)&7)<6)bg_select=rec_cell<rec_cells ? 9:10;
    end
    if(!rec_shortcut && !view[42] && (rec_state==0 || rec_state==1 || rec_state==6) && x>=336 && x<608 && y>=100 && y<116)begin
     active=1;yy=y-100;line=rec_state==6 ? `A_REC_ACTIVE_KEYS:`A_REC_IDLE_KEYS;
    end
   end
  end
  if(de && state==0 && view[106] && !(view[18] || view[42] || rec_card) && x>=152 && x<504 && y>=448 && y<472)begin
   overlay=1;bg_select=11;active=x>=160 && x<496 && y>=452 && y<468;size=0;yy=y-452;xx=x-160;direct=0;line=`A_UI_DEMO_KEYS;ink=24'hedf3f7;
  end
 end
endmodule
