`timescale 1ns/1ps
// Copy each CRC-approved packet into A's 512-byte image buffer before
// waiting on SDRAM. This releases parser RAM for READY/APPLIED/analysis.
// ACK retires B's held block; only IMAGE_REQ grants the next credit.
// ACK duplicates without copying or publishing the block twice.
module scene_image_buffer(
 input wire clk,rst_n,begin_file,input wire [31:0] live_epoch,file_bytes,input wire [7:0] file_id,
 input wire packet_valid,output reg packet_ready,
 input wire [31:0] packet_epoch,packet_offset,input wire [7:0] packet_file,input wire [9:0] packet_length,
 output reg [8:0] packet_addr,input wire [7:0] packet_data,
 output reg reply_valid,input wire reply_ready,output reg reply_retry,output reg [31:0] reply_offset,
 output wire can_request,output reg [31:0] next_offset,
 output wire out_valid,input wire out_ready,output wire [7:0] out_data,output wire out_last,
 output reg file_done,output reg [31:0] source_crc,
 output reg [31:0] published_bytes,duplicates,rejections,stale_packets
);
 `include "crc32_defs.vh"
 (* ram_style="block" *) reg [7:0] buffer[0:511];
 reg [7:0] read_q;
 reg [8:0] read_addr;
 reg [1:0] copy_state,stream_state;
 reg busy,last_valid;
 reg [31:0] last_offset,crc;
 reg [9:0] last_length,copy_length,copy_index,read_index;
 reg final_block;
 reg [31:0] held_epoch,held_bytes;
 reg [7:0] held_file;
 wire [32:0] end_offset={1'b0,next_offset}+packet_length;
 wire [31:0] remaining=held_bytes-next_offset;
 wire [9:0] required_length=remaining>=512 ? 10'd512 : remaining[9:0];
 assign can_request=!busy && copy_state==0 && !reply_valid && !file_done;
 assign out_valid=busy && stream_state==2;
 assign out_data=read_q;
 assign out_last=out_valid && final_block && read_index==copy_length-1;
 always @(posedge clk)begin
  read_q<=buffer[read_addr];
  if(copy_state==3)buffer[copy_index[8:0]]<=packet_data;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   packet_ready<=0;packet_addr<=0;reply_valid<=0;reply_retry<=0;reply_offset<=0;
   next_offset<=0;file_done<=0;source_crc<=0;published_bytes<=0;
   duplicates<=0;rejections<=0;stale_packets<=0;read_addr<=0;
   copy_state<=0;stream_state<=0;busy<=0;last_valid<=0;
   last_offset<=0;last_length<=0;copy_length<=0;copy_index<=0;read_index<=0;
   final_block<=0;held_epoch<=0;held_bytes<=0;held_file<=0;crc<=32'hffffffff;
  end else begin
   packet_ready<=0;
   if(reply_valid && reply_ready)reply_valid<=0;
   if(begin_file && !busy && copy_state==0)begin
    held_epoch<=live_epoch;held_file<=file_id;held_bytes<=file_bytes;
    next_offset<=0;file_done<=0;source_crc<=0;published_bytes<=0;
    last_valid<=0;crc<=32'hffffffff;reply_valid<=0;
   end else if(copy_state==0 && packet_valid && !packet_ready && (!reply_valid || reply_ready))begin
    if(packet_epoch!=held_epoch || packet_file!=held_file)begin
     stale_packets<=stale_packets+1'b1;packet_ready<=1;
    end else if(last_valid && packet_offset==last_offset && packet_length==last_length)begin
     duplicates<=duplicates+1'b1;packet_ready<=1;
     reply_valid<=1;reply_retry<=0;reply_offset<=last_offset;
    end else if(busy || file_done || packet_offset!=next_offset || packet_length==0 ||
       packet_length!=required_length || end_offset>{1'b0,held_bytes})begin
     rejections<=rejections+1'b1;packet_ready<=1;
     reply_valid<=1;reply_retry<=1;reply_offset<=next_offset;
    end else begin
     copy_length<=packet_length;copy_index<=0;
     packet_addr<=0;copy_state<=1;
    end
   end
   case(copy_state)
    1:copy_state<=2;
    2:copy_state<=3;
    3:begin
     if(copy_index==copy_length-1)begin
      copy_state<=0;packet_ready<=1;reply_valid<=1;reply_retry<=0;reply_offset<=next_offset;
      last_offset<=next_offset;last_length<=copy_length;last_valid<=1;
      next_offset<=next_offset+copy_length;final_block<=next_offset+copy_length==held_bytes;
      busy<=1;read_addr<=0;read_index<=0;stream_state<=0;
     end else begin copy_index<=copy_index+1'b1;packet_addr<=packet_addr+1'b1;copy_state<=1;end
    end
   endcase
   if(busy)case(stream_state)
    0:stream_state<=1;
    1:stream_state<=2;
    2:if(out_ready)begin
     crc<=crc32_byte(crc,read_q);published_bytes<=published_bytes+1'b1;
     if(read_index==copy_length-1)begin
      busy<=0;stream_state<=0;
      if(final_block)begin file_done<=1;source_crc<=~crc32_byte(crc,read_q);end
     end else begin read_index<=read_index+1'b1;read_addr<=read_addr+1'b1;stream_state<=0;end
    end
   endcase
  end
 end
endmodule
