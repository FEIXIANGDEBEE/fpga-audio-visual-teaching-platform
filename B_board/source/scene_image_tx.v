`timescale 1ns/1ps
// Stop-and-wait transmission with one block of lookahead in the other RAM bank.
// Keep the transmitted bank unchanged until ACK. Send lookahead bytes only
// after the matching request arrives.
module scene_image_tx #(parameter ACK_TIMEOUT=5000000,MAX_RETRIES=3)(
 input wire clk,rst_n,
 input wire begin_file,input wire [31:0] live_epoch,file_bytes,input wire [7:0] file_id,input wire file_trusted,
 output wire begin_ready,
 input wire message_valid,input wire [7:0] message_type,message_file,
 input wire [31:0] message_epoch,message_offset,
 output wire file_demand,file_available,output wire [31:0] file_offset,output wire [3:0] file_number,
 input wire file_accepted,file_valid,file_error,input wire [7:0] file_data,
 output wire send_valid,input wire send_ready,send_done,
 output wire [31:0] send_epoch,send_offset,output wire [7:0] send_file,send_flags,output wire [9:0] send_length,
 input wire [8:0] payload_addr,output reg [7:0] payload_data,
 output reg file_done,fault,output reg [31:0] source_crc,next_offset,
 output reg [31:0] retries,stale_messages,rejections,bytes_read
);
 `include "scene_protocol.vh"
 `include "crc32_defs.vh"
 localparam IDLE=0,WAIT_REQUEST=1,FILL=2,SEND=3,WAIT_TX=4,WAIT_ACK=5,FAILED=6,WAIT_AHEAD=7;
 reg [2:0] state;
 (* force_ram, ram_style="bram" *) reg [7:0] copy[0:1023];
 reg [31:0] held_epoch,held_bytes,block_offset,crc,timer;
 reg [7:0] held_file,retry_count;
 reg [9:0] block_length,fill_index,ahead_length,ahead_index;
 reg [31:0] ahead_offset;
 reg pending,active_bank,ahead_fetch,ahead_valid;
 wire match_file=message_epoch==held_epoch && message_file==held_file;
 wire matching=match_file && message_offset==block_offset;
 wire [31:0] remaining=held_bytes-next_offset;
 wire [31:0] after_current=block_offset+block_length;
 wire [31:0] next_remaining=held_bytes-after_current;
 wire fetch_active=state==FILL || ahead_fetch;
 wire [9:0] fetch_index=state==FILL ? fill_index:ahead_index;
 wire [9:0] fetch_length=state==FILL ? block_length:ahead_length;
 wire fetch_bank=state==FILL ? active_bank:!active_bank;
 assign begin_ready=(state==IDLE || state==WAIT_REQUEST || state==FAILED) && !pending && !ahead_fetch;
 assign file_demand=fetch_active && !fault;
 assign file_available=file_demand && !pending;
 assign file_offset=state==FILL ? block_offset+fill_index:ahead_offset+ahead_index;
 assign file_number=held_file[3:0];
 assign send_valid=state==SEND;assign send_epoch=held_epoch;assign send_offset=block_offset;
 assign send_file=held_file;assign send_length=block_length;
 assign send_flags={7'd0,after_current==held_bytes};
 always @(posedge clk)begin
  payload_data<=copy[{active_bank,payload_addr}];
  if(fetch_active && file_valid && pending && !file_error)copy[{fetch_bank,fetch_index[8:0]}]<=file_data;
 end
 task resend;
  begin
   if(retry_count<MAX_RETRIES)begin retry_count<=retry_count+1'b1;retries<=retries+1'b1;timer<=0;state<=SEND;end
   else begin fault<=1;state<=FAILED;ahead_fetch<=0;ahead_valid<=0;end
  end
 endtask
 // Promote only after ACK and a complete lookahead fill. Nonblocking updates
 // leave the old TX bank untouched until both conditions hold.
 task promote_ahead;
  begin
   active_bank<=!active_bank;block_offset<=ahead_offset;block_length<=ahead_length;
   ahead_valid<=0;retry_count<=0;state<=SEND;
  end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;held_epoch<=0;held_bytes<=0;held_file<=0;block_offset<=0;block_length<=0;fill_index<=0;
   pending<=0;crc<=32'hffffffff;timer<=0;retry_count<=0;file_done<=0;fault<=0;source_crc<=0;next_offset<=0;
   retries<=0;stale_messages<=0;rejections<=0;bytes_read<=0;active_bank<=0;
   ahead_fetch<=0;ahead_valid<=0;ahead_offset<=0;ahead_length<=0;ahead_index<=0;
  end else begin
   if(begin_file && begin_ready)begin
    held_epoch<=live_epoch;held_bytes<=file_bytes;held_file<=file_id;block_offset<=0;next_offset<=0;
    crc<=32'hffffffff;timer<=0;retry_count<=0;file_done<=0;fault<=0;source_crc<=0;bytes_read<=0;
    active_bank<=0;ahead_fetch<=0;ahead_valid<=0;ahead_offset<=0;ahead_length<=0;ahead_index<=0;
    if(file_bytes==0 || file_bytes>67108864 || file_id>9 || !file_trusted)begin fault<=1;state<=FAILED;end
    else state<=WAIT_REQUEST;
   end else begin
    // A failed lookahead can leave one response in flight. Drain it before a new
    // begin_file; the drained byte cannot publish data or update CRC.
    if(!fetch_active && pending && (file_valid || file_error))pending<=0;
    if(file_accepted && fetch_active && !pending)pending<=1;
    if(fetch_active && (file_valid || file_error))begin
     pending<=0;
     if(!pending || file_error)begin fault<=1;state<=FAILED;ahead_fetch<=0;ahead_valid<=0;end
     else begin
      crc<=crc32_byte(crc,file_data);bytes_read<=bytes_read+1'b1;
      if(state==FILL)begin
       if(fill_index==fetch_length-1)begin state<=SEND;fill_index<=0;end
       else fill_index<=fill_index+1'b1;
      end else begin
       if(ahead_index==fetch_length-1)begin ahead_fetch<=0;ahead_valid<=1;ahead_index<=0;end
       else ahead_index<=ahead_index+1'b1;
      end
     end
    end
    // Begin lookahead once the TX block is stable and the preceding fill is complete.
    if((state==SEND || state==WAIT_TX || state==WAIT_ACK) && !ahead_fetch && !ahead_valid && after_current<held_bytes)begin
     ahead_offset<=after_current;ahead_length<=next_remaining>=512 ? 512:next_remaining[9:0];
     ahead_index<=0;ahead_fetch<=1;
    end
    if(state==WAIT_AHEAD && ahead_valid)promote_ahead();
    if(state==SEND && send_ready)state<=WAIT_TX;
    if(state==WAIT_TX && send_done)begin state<=WAIT_ACK;timer<=0;end
    if(state==WAIT_ACK && !(message_valid && matching &&
       (message_type==`SCENE_IMAGE_ACK || message_type==`SCENE_IMAGE_RETRY || message_type==`SCENE_IMAGE_REQ)))begin
     if(timer>=ACK_TIMEOUT-1)resend();else timer<=timer+1'b1;
    end
    if(message_valid)begin
     if(!match_file)stale_messages<=stale_messages+1'b1;
     else if(state==WAIT_REQUEST && message_type==`SCENE_IMAGE_REQ && message_offset==next_offset && !file_done)begin
      retry_count<=0;
      if(next_offset==0)begin
       block_offset<=0;block_length<=remaining>=512 ? 512:remaining[9:0];fill_index<=0;pending<=0;state<=FILL;
      end else if(ahead_valid && ahead_offset==next_offset)promote_ahead();
      else if(ahead_fetch && ahead_offset==next_offset)state<=WAIT_AHEAD;
      else begin fault<=1;state<=FAILED;end
     end else if(state==WAIT_ACK && matching && message_type==`SCENE_IMAGE_ACK)begin
      next_offset<=after_current;state<=WAIT_REQUEST;timer<=0;
      if(after_current==held_bytes)begin file_done<=1;source_crc<=~crc;end
     end else if(state==WAIT_AHEAD && message_type==`SCENE_IMAGE_REQ && message_offset==next_offset)begin
      // Credit is already held while lookahead waits for SD/audio arbitration.
      // Ignore the receiver's periodic duplicate credit.
     end else if(state==WAIT_ACK && matching &&
       (message_type==`SCENE_IMAGE_RETRY || message_type==`SCENE_IMAGE_REQ))resend();
     else if(message_type==`SCENE_IMAGE_ACK && message_offset<next_offset)begin end
     else rejections<=rejections+1'b1;
    end
    // Read error takes priority over same-cycle ACK, retry and promotion.
    if(fetch_active && (file_valid || file_error) && (!pending || file_error))begin
     fault<=1;state<=FAILED;ahead_fetch<=0;ahead_valid<=0;
    end
   end
  end
 end
endmodule
