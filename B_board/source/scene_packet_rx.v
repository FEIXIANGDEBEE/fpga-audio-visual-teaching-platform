`timescale 1ns/1ps
`include "scene_protocol.vh"
// Publish a packet only after CRC passes. All packet types share one
// synchronous 512-byte RAM, locked until packet_ready consumes the packet.
// The byte link is independent of SD/FAT/FFT; control packets fit in 64 bytes.
module scene_packet_rx #(parameter MAX_PAYLOAD=512,TIMEOUT=5000000)(
 input wire clk,rst_n,input wire [7:0] byte_data,input wire byte_valid,output wire byte_ready,
 output reg packet_valid,input wire packet_ready,
 output reg [7:0] kind,id,flags,output reg [31:0] epoch,offset,output reg [9:0] length,
 input wire [8:0] payload_addr,output reg [7:0] payload_data,
 output reg [31:0] packets,crc_errors,format_errors,timeouts
);
 `include "crc32_defs.vh"
 localparam SYNC=0,HEADER=1,BODY=2,TRAILER=3;
 reg [1:0] state;
 reg sync_byte;
 reg [4:0] index;
 reg [9:0] body_index;
 reg [31:0] crc,received_crc,timer;
 reg [7:0] length_high;
 (* ram_style="block" *) reg [7:0] payload[0:511];
 assign byte_ready=!packet_valid;
 always @(posedge clk)begin
  payload_data<=payload[payload_addr];
  if(byte_valid && byte_ready && state==BODY)payload[body_index[8:0]]<=byte_data;
 end
 wire [15:0] decoded_length={length_high,byte_data};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=SYNC;sync_byte<=0;index<=0;body_index<=0;crc<=32'hffffffff;received_crc<=0;timer<=0;length_high<=0;
   packet_valid<=0;kind<=0;id<=0;flags<=0;epoch<=0;offset<=0;length<=0;
   packets<=0;crc_errors<=0;format_errors<=0;timeouts<=0;
  end else begin
   if(packet_valid && packet_ready)packet_valid<=0;
   if(byte_valid && byte_ready)begin
    timer<=0;
    case(state)
     SYNC:begin
      if(sync_byte && byte_data==8'haa)begin
       crc<=crc32_byte(crc32_byte(32'hffffffff,8'hd5),8'haa);index<=2;state<=HEADER;sync_byte<=0;
      end else sync_byte<=byte_data==8'hd5;
     end
     HEADER:begin
      crc<=crc32_byte(crc,byte_data);index<=index+1'b1;
      case(index)
       2:if(byte_data!=8'h13)begin format_errors<=format_errors+1'b1;state<=SYNC;sync_byte<=byte_data==8'hd5;end
       3:kind<=byte_data;
       4,5,6,7:epoch<={epoch[23:0],byte_data};
       8,9,10,11:offset<={offset[23:0],byte_data};
       12:id<=byte_data;
       13:flags<=byte_data;
       14:length_high<=byte_data;
       15:begin
        if(decoded_length>MAX_PAYLOAD || (kind!=`SCENE_IMAGE_DATA && decoded_length>44))begin
         format_errors<=format_errors+1'b1;state<=SYNC;sync_byte<=0;
        end else begin
         length<=decoded_length[9:0];body_index<=0;index<=0;received_crc<=0;
         state<=decoded_length==0 ? TRAILER : BODY;
        end
       end
      endcase
     end
     BODY:begin
      crc<=crc32_byte(crc,byte_data);
      if(body_index==length-1)begin index<=0;received_crc<=0;state<=TRAILER;end
      else body_index<=body_index+1'b1;
     end
     TRAILER:begin
      received_crc<={received_crc[23:0],byte_data};index<=index+1'b1;
      if(index==3)begin
       if({received_crc[23:0],byte_data}==~crc)begin packet_valid<=1;packets<=packets+1'b1;end
       else crc_errors<=crc_errors+1'b1;
       state<=SYNC;sync_byte<=0;
      end
     end
    endcase
   end else if(!packet_valid && (state!=SYNC || sync_byte))begin
    if(timer==TIMEOUT-1)begin
     state<=SYNC;sync_byte<=0;timer<=0;timeouts<=timeouts+1'b1;
    end else timer<=timer+1'b1;
   end
  end
 end
endmodule
