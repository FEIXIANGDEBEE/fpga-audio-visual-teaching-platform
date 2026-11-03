`timescale 1ns/1ps
// One parser checks four WAV entries. Publish a descriptor only after the
// bounded RIFF chunk list passes; a failed entry does not invalidate its peers.
// Descriptor = {stereo,frames32,data_bytes32,data_offset32}.
module scene_wav_catalog #(parameter MAX_FILE_BYTES=67108864)(
 input wire clk,rst_n,start,input wire [13:0] file_valid,
 output wire [3:0] catalog_addr,input wire [63:0] catalog_data,
 output wire byte_req,output wire [31:0] byte_offset,output wire [3:0] byte_file,
 input wire byte_ready,byte_valid,byte_error,input wire [7:0] byte_data,
 output reg done,output reg [3:0] valid_mask,rejected_mask,
 input wire [1:0] descriptor_addr,output wire [96:0] descriptor,
 output reg [7:0] last_error
);
 localparam IDLE=0,SELECT=1,SETTLE=2,BEGIN_PARSE=3,PARSING=4,NEXT=5,HALT=6,STARTED=7;
 reg [2:0] state;reg [1:0] entry;
 reg header_start,pending;reg [31:0] file_bytes;
 wire hreq,hdone,herror,hstereo;wire [7:0] hcode;
 wire [31:0] hoff,hbytes,hframes,request_offset;
 // Native descriptor RAM has a one-cycle read. parser/valid/done qualifies publication.
 wire descriptor_write=state==PARSING && !herror && hdone;
 wire [96:0] descriptor_d={hstereo,hframes,hbytes,hoff};
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(97),.DATA_WIDTH_B(97),.ADDR_WIDTH_A(2),.ADDR_WIDTH_B(2),
  .DATA_DEPTH_A(4),.DATA_DEPTH_B(4),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) descriptors_ram(
  .doa(),.dob(descriptor),.dia(descriptor_d),.dib(97'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),
  .clka(clk),.clkb(clk),.wea(descriptor_write),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
  .addra(entry),.addrb(descriptor_addr));
 assign catalog_addr={2'b0,entry}+4'd10;
 assign byte_file=catalog_addr;
 assign byte_req=state==PARSING && hreq && !pending && byte_ready;
 assign byte_offset=request_offset;
 scene_wav_header #(.MAX_FILE_BYTES(MAX_FILE_BYTES)) parser(clk,rst_n,header_start,file_bytes,hreq,request_offset,
  byte_valid && pending && state==PARSING,byte_data,byte_error && pending && state==PARSING,
  hdone,herror,hcode,hstereo,hoff,hbytes,hframes);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;entry<=0;header_start<=0;pending<=0;file_bytes<=0;
   done<=0;valid_mask<=0;rejected_mask<=0;last_error<=0;
  end else begin
   header_start<=0;
   if(byte_req)pending<=1;
   if(byte_valid || byte_error)pending<=0;
   case(state)
    IDLE:if(start)begin done<=0;valid_mask<=0;rejected_mask<=0;last_error<=0;entry<=0;state<=SELECT;end
    SELECT:state<=SETTLE;
    SETTLE:begin
     if(!file_valid[catalog_addr])begin rejected_mask[entry]<=1;last_error<=8'h20;state<=NEXT;end
     else begin file_bytes<=catalog_data[63:32];state<=BEGIN_PARSE;end
    end
    BEGIN_PARSE:begin header_start<=1;pending<=0;state<=STARTED;end
    STARTED:state<=PARSING;
    PARSING:begin
     if(herror)begin rejected_mask[entry]<=1;last_error<=hcode;state<=NEXT;end
     else if(hdone)begin
      valid_mask[entry]<=1;state<=NEXT;
     end
    end
    NEXT:if(entry==3)begin done<=1;state<=HALT;end else begin entry<=entry+1'b1;state<=SELECT;end
    HALT:if(!start)state<=IDLE;
    default:state<=IDLE;
   endcase
  end
 end
endmodule
