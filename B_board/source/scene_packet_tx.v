`timescale 1ns/1ps
`include "scene_protocol.vh"
// 16-byte header for control, image and analysis packets:
// D5 AA 13 type epoch32 offset/transaction32 file/scene8 flags8 length16.
// CRC32 covers header and payload, followed by four big-endian CRC bytes.
// Only IMAGE_DATA can exceed 44 payload bytes; other complete packets fit 64.
// The producer holds payload RAM unchanged through done.
module scene_packet_tx #(parameter MAX_PAYLOAD=512)(
 input wire clk,rst_n,start,input wire [7:0] kind,id,flags,
 input wire [31:0] epoch,offset,input wire [9:0] length,
 output wire ready,output reg done,output reg [31:0] rejected,
 output reg [8:0] payload_addr,input wire [7:0] payload_data,
 output reg [7:0] byte_data,output wire byte_valid,input wire byte_ready
);
 `include "crc32_defs.vh"
 localparam IDLE=0,HEADER=1,BODY_WAIT=2,BODY_SEND=3,TRAILER=4;
 reg [2:0] state;
 reg [4:0] index;
 reg wait_bit;
 reg [7:0] held_kind,held_id,held_flags;
 reg [31:0] held_epoch,held_offset,crc,final_crc;
 reg [9:0] held_length,body_index;
 assign ready=state==IDLE;
 assign byte_valid=state==HEADER || state==BODY_SEND || state==TRAILER;
 always @*begin
  byte_data=0;
  if(state==HEADER)case(index)
   0:byte_data=8'hd5;1:byte_data=8'haa;2:byte_data=8'h13;3:byte_data=held_kind;
   4:byte_data=held_epoch[31:24];5:byte_data=held_epoch[23:16];6:byte_data=held_epoch[15:8];7:byte_data=held_epoch[7:0];
   8:byte_data=held_offset[31:24];9:byte_data=held_offset[23:16];10:byte_data=held_offset[15:8];11:byte_data=held_offset[7:0];
   12:byte_data=held_id;13:byte_data=held_flags;14:byte_data={6'd0,held_length[9:8]};15:byte_data=held_length[7:0];
  endcase
  else if(state==BODY_SEND)byte_data=payload_data;
  else if(state==TRAILER)case(index)
   0:byte_data=final_crc[31:24];1:byte_data=final_crc[23:16];2:byte_data=final_crc[15:8];3:byte_data=final_crc[7:0];
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;index<=0;wait_bit<=0;payload_addr<=0;done<=0;rejected<=0;
   held_kind<=0;held_id<=0;held_flags<=0;held_epoch<=0;held_offset<=0;held_length<=0;
   crc<=32'hffffffff;final_crc<=0;body_index<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin
     if(length>MAX_PAYLOAD || (kind!=`SCENE_IMAGE_DATA && length>44))rejected<=rejected+1'b1;
     else begin
      held_kind<=kind;held_id<=id;held_flags<=flags;held_epoch<=epoch;held_offset<=offset;held_length<=length;
      crc<=32'hffffffff;index<=0;payload_addr<=0;body_index<=0;state<=HEADER;
     end
    end
    HEADER:if(byte_ready)begin
     crc<=crc32_byte(crc,byte_data);
     if(index==15)begin
      index<=0;
      if(held_length==0)begin final_crc<=~crc32_byte(crc,byte_data);state<=TRAILER;end
      else begin wait_bit<=0;state<=BODY_WAIT;end
     end else index<=index+1'b1;
    end
    BODY_WAIT:if(wait_bit)state<=BODY_SEND;else wait_bit<=1;
    BODY_SEND:if(byte_ready)begin
     crc<=crc32_byte(crc,byte_data);
     if(body_index==held_length-1)begin final_crc<=~crc32_byte(crc,byte_data);index<=0;state<=TRAILER;end
     else begin body_index<=body_index+1'b1;payload_addr<=payload_addr+1'b1;wait_bit<=0;state<=BODY_WAIT;end
    end
    TRAILER:if(byte_ready)begin
     if(index==3)begin done<=1;state<=IDLE;end else index<=index+1'b1;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
