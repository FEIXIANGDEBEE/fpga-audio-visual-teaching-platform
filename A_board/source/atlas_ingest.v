`timescale 1ns/1ps
`include "atlas_contract.vh"
// Decode layered pages with full-height foreground. Ordinary pages use their
// own loader. Read back each auxiliary and BASE word against its source asset.
module atlas_ingest #(parameter TIMEOUT_CYCLES=600000000)(
 input wire clk,rst_n,start,memory_ready,input wire [1:0] slot,
 input wire [31:0] file_bytes,input wire stream_valid,input wire [7:0] stream_data,
 output wire stream_ready,input wire stream_done,input wire [31:0] stream_crc,
 output wire busy,output reg image_ready,fault,output reg [7:0] error_code,
 output wire req_valid,req_write,output wire [20:0] req_addr,output wire [31:0] req_data,
 input wire req_ready,rsp_valid,input wire [31:0] rsp_data,input wire rsp_error,
 output reg [31:0] words_written
);
 `include "crc32_defs.vh"
 localparam IDLE=0,INPUT=1,WRITE=2,WAIT_WRITE=3,READ=4,WAIT_READ=5,CRC=6,CHECK=7,PUBLISH=8,FAILED=9,FINISH=10;
 reg [3:0] state;reg [1:0] held_slot;reg [31:0] offset,timer;
 reg [10:0] x;reg [9:0] y;reg [1:0] channel;reg [7:0] blue,green;reg [23:0] premul;
 reg [20:0] address,data_address;reg [31:0] data_word,crc_word,crc;reg [1:0] crc_phase,plane;
 reg [18:0] index;reg [18:0] base_count;reg [17:0] bg_count;reg [16:0] fg_count;
 wire [23:0] rgb={stream_data,green,blue};
 wire [20:0] slot_base=held_slot==0 ? 614400:held_slot==1 ? 921600:held_slot==2 ? 1228800:1536000;
 // Reuse y products without adding state: 213*y = 3*(64*y+7*y);
 // 442*y = 2*(213*y)+16*y.
 wire [12:0] y7=({3'd0,y}<<3)-{3'd0,y};
 wire [16:0] y71=({7'd0,y}<<6)+{4'd0,y7};
 wire [17:0] y213=({1'b0,y71}<<1)+{1'b0,y71};
 // Read FG for y>=320; below that, pixel_address selects BG/BASE.
 wire [20:0] fg_row={3'd0,y213}-21'd68160;
 wire [20:0] bg_row=({3'd0,y213}<<1)+({11'd0,y}<<4);
 wire [20:0] base_row=({11'd0,y}<<9)+({11'd0,y}<<7);
 wire [20:0] pixel_address=y<480 && x<640 ? slot_base+base_row+x:y<320 ? bg_row+x-640:21'd141568+fg_row+((x-11'd640)>>1);
 assign req_valid=state==WRITE || state==READ;
 assign req_write=state==WRITE;
 assign req_addr=state==WRITE ? data_address:plane==0 ? {2'd0,index}:plane==1 ? 21'd141568+index:slot_base+index;
 assign req_data=data_word;
 assign stream_ready=state==INPUT;
 assign busy=state!=IDLE && state!=FAILED;
 function header_bad;input [31:0] n;input [7:0] b;begin
  case(n)
   0:header_bad=b!=8'h42;1:header_bad=b!=8'h4d;
   2:header_bad=b!=8'h36;3:header_bad=b!=8'h30;4:header_bad=b!=8'h2a;5:header_bad=b!=0;
   10:header_bad=b!=54;11,12,13:header_bad=b!=0;14:header_bad=b!=40;15,16,17:header_bad=b!=0;
   18:header_bad=b!=0;19:header_bad=b!=5;20,21:header_bad=b!=0;
   22:header_bad=b!=8'hd0;23:header_bad=b!=2;24,25:header_bad=b!=0;
   26:header_bad=b!=1;27:header_bad=b!=0;28:header_bad=b!=24;29,30,31,32,33:header_bad=b!=0;
   34:header_bad=b!=0;35:header_bad=b!=8'h30;36:header_bad=b!=8'h2a;37:header_bad=b!=0;
   default:header_bad=0;
  endcase
 end endfunction
 function [7:0] marker;input [3:0] n;begin
  case(n)0:marker="V";1:marker="1";2:marker="2";3:marker="L";4:marker=4;5:marker=4;6:marker="P";default:marker=0;endcase
 end endfunction
 task fail;input [7:0] code;begin state<=FAILED;fault<=1;image_ready<=0;error_code<=code;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;held_slot<=0;offset<=0;timer<=0;x<=0;y<=719;channel<=0;blue<=0;green<=0;premul<=0;
   address<=0;data_address<=0;data_word<=0;crc_word<=0;crc<=32'hffffffff;crc_phase<=0;plane<=0;index<=0;
   base_count<=0;bg_count<=0;fg_count<=0;words_written<=0;image_ready<=0;fault<=0;error_code<=0;
  end else begin
   image_ready<=0;
   if(busy)begin
    if((stream_valid && stream_ready)||rsp_valid||state==CRC)timer<=0;else timer<=timer+1'b1;
    if(timer==TIMEOUT_CYCLES-1)fail(8'hd0);
   end
   case(state)
    IDLE:if(start && memory_ready)begin
     fault<=0;error_code<=0;held_slot<=slot;offset<=0;timer<=0;x<=0;y<=719;channel<=0;
     words_written<=0;base_count<=0;bg_count<=0;fg_count<=0;state<=INPUT;
     if(file_bytes!=2764854)fail(8'hc1);
    end
    INPUT:if(stream_valid)begin
     offset<=offset+1'b1;
     if(offset<54)begin if(header_bad(offset,stream_data))fail(8'hc2);end
     else begin
      if(channel==0)blue<=stream_data;else if(channel==1)green<=stream_data;
      if(channel==2)begin
       channel<=0;
       if(x==1279)begin x<=0;if(y!=0)y<=y-1'b1;end else x<=x+1'b1;
       if((y<480 && x<640)||(y<320 && x>=640 && x<1082)||(y>=320 && y<640 && x>=640 && x<1066 && x[0]))begin
        data_address<=pixel_address;data_word<=y>=320 && y<640 && x>=640 ?  {stream_data,premul}:{8'd0,rgb};state<=WRITE;
        if(y<480 && x<640)base_count<=base_count+1'b1;else if(y<320)bg_count<=bg_count+1'b1;else fg_count<=fg_count+1'b1;
        if(y>=320 && y<640 && x>=640 && x<1066 && (stream_data!=green || green!=blue))fail(8'hc4);
       end
       if(y>=320 && y<640 && x>=640 && x<1066 && !x[0])premul<=rgb;
      end else channel<=channel+1'b1;
     end
     if(offset>=1014 && offset<1026 && stream_data!=marker(offset-1014))fail(8'hc3);
     if(offset==2764853)state<=FINISH;
    end
    WRITE:if(req_ready)state<=WAIT_WRITE;
    WAIT_WRITE:if(rsp_valid)begin
     if(rsp_error)fail(8'hc5);else begin words_written<=words_written+1'b1;state<=INPUT;end
    end
    FINISH:if(stream_done)begin
     if(stream_crc!=`ATLAS_SOURCE_CRC || base_count!=307200 || bg_count!=141440 || fg_count!=68160 || words_written!=516800 || channel!=0)fail(8'hc6);
     else begin plane<=0;index<=0;crc<=32'hffffffff;state<=READ;end
    end
    READ:if(req_ready)state<=WAIT_READ;
    WAIT_READ:if(rsp_valid)begin
     if(rsp_error)fail(8'hc7);else begin crc_word<=rsp_data;crc_phase<=0;state<=CRC;end
    end
    CRC:begin
     crc<=crc32_byte(crc,crc_word[31:24]);crc_word<={crc_word[23:0],8'd0};crc_phase<=crc_phase+1'b1;
     if(crc_phase==3)begin
      if(index==(plane==2 ? 307199:plane==1 ? 68159:141439))state<=CHECK;else begin index<=index+1'b1;state<=READ;end
     end
    end
    CHECK:if((~crc)!=(plane==0 ? `ATLAS_BG_CRC:plane==1 ? `ATLAS_FG_CRC:`ATLAS_BASE_CRC))fail(8'hc8);
     else if(plane==2)state<=PUBLISH;else begin plane<=plane+1'b1;index<=0;crc<=32'hffffffff;state<=READ;end
    PUBLISH:begin image_ready<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
