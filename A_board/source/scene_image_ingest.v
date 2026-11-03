`timescale 1ns/1ps
// Cache slots occupy [614400,1843200); work frames occupy [0,614400).
// Publish a slot after source and target complete, display-order CRC passes,
// and independent SDRAM readback matches the writer-order CRC.
module scene_image_ingest #(parameter TIMEOUT_CYCLES=600000000)(
 input wire clk,rst_n,memory_ready,start,input wire [1:0] scene,
 input wire [31:0] file_bytes,input wire stream_valid,input wire [7:0] stream_data,
 output wire stream_ready,input wire stream_done,input wire [31:0] stream_crc,
 output wire busy,output reg image_ready,output reg [3:0] trusted,
 output wire [31:0] display_crc,output reg [127:0] source_crcs,geometries,
 output reg fault,output reg [7:0] error_code,
 output wire req_valid,req_write,output wire [20:0] req_addr,output wire [31:0] req_data,
 input wire req_ready,rsp_valid,input wire [31:0] rsp_data,input wire rsp_error,
 output wire [31:0] words_written,output reg [31:0] max_wait,
 output wire [351:0] header_diagnostics,
 output wire [69:0] qualified_geometry
);
 `include "crc32_defs.vh"
 localparam IDLE=0,LOAD=1,READ=2,CRC=3,VERIFY=4,PUBLISH=5,FAILED=6;
 reg [2:0] state;reg [1:0] held_scene;reg [31:0] held_size,timer;
 reg bmp_start,writer_start;wire bmp_done,bmp_fault;wire [7:0] bmp_error;
 wire [37:0] actual_fit;wire [15:0] sw,sh;wire [31:0] raw_bytes,raw_crc,rows,fallback,dropped;wire [18:0] targets;
 assign qualified_geometry={sw,sh,actual_fit};
 wire bpv,bpr;wire [23:0] bpd;
 wire gen=1'b0;
 scene_bmp_stream bmp(clk,rst_n,bmp_start,1'b0,held_size,
  stream_valid && !gen,stream_data,stream_ready,bpv,bpd,bpr,bmp_done,bmp_fault,bmp_error,
  sw,sh,raw_bytes,raw_crc,rows,fallback,dropped,targets,header_diagnostics,actual_fit);
 wire wpv=bpv;
 wire [23:0] wpd=bpd;
 wire wready,wbusy,wdone,werror;wire [20:0] werror_addr;
 wire [31:0] wmax,wstalls;wire wrv;wire [20:0] wra;wire [31:0] wrd;
 reg [2:0] write_phase;
 // LOAD and readback CRC are exclusive and share one byte datapath.
 reg [31:0] work_crc,crc_word,expected_write_crc;
 wire write_ready=req_ready && state==LOAD && write_phase==0;
 assign bpr=wready && !gen;
 tf_fifo_writer #(.BASE(21'd0)) writer(clk,rst_n,writer_start,1'b0,wpv && state==LOAD,wpd,
  wready,wbusy,wdone,werror,words_written,werror_addr,wmax,wstalls,wrv,,wra,wrd,,write_ready,
  rsp_valid && state==LOAD,rsp_error,);
 reg read_pending,reverse_pass;reg [18:0] read_index;reg [20:0] row_base;
 reg [9:0] read_x;reg [1:0] read_phase;reg [31:0] canonical_crc;
 assign display_crc=canonical_crc;
 wire [20:0] slot_base=held_scene==0 ? 614400 : held_scene==1 ? 921600 : held_scene==2 ? 1228800 : 1536000;
 assign req_valid=state==LOAD ? wrv && write_phase==0 : state==READ && !read_pending;
 assign req_write=state==LOAD;
 assign req_addr=slot_base+(state==LOAD ? wra : reverse_pass ? row_base+read_x : {2'd0,read_index});
 assign req_data=state==LOAD ? wrd : 0;
 assign busy=state!=IDLE && state!=FAILED;
 wire [7:0] crc_byte=crc_word[31:24];
 wire [31:0] crc_next=crc32_byte(work_crc,crc_byte);
 // Measure missing progress for throttled files. Request acceptance alone
 // does not complete work or reset the progress requirement.
 wire progress=(state==LOAD && ((stream_valid && stream_ready) || (wpv && wready) || rsp_valid)) ||
  (state==READ && read_pending && rsp_valid) || state==CRC;
 task fail;input [7:0] code;
  begin fault<=1;error_code<=code;state<=FAILED;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;held_scene<=0;held_size<=0;timer<=0;bmp_start<=0;writer_start<=0;
   image_ready<=0;trusted<=0;source_crcs<=0;geometries<=0;fault<=0;error_code<=0;max_wait<=0;
   write_phase<=0;work_crc<=32'hffffffff;crc_word<=0;expected_write_crc<=0;
   read_pending<=0;reverse_pass<=0;read_index<=0;row_base<=0;read_x<=0;read_phase<=0;
   canonical_crc<=0;
  end else begin
   bmp_start<=0;writer_start<=0;image_ready<=0;
   if(busy)begin if(progress)timer<=0;else timer<=timer+1'b1;if(timer>max_wait)max_wait<=timer;end
   if(state==LOAD && wrv && write_ready)begin crc_word<=wrd;write_phase<=1;end
   else if(write_phase!=0)begin
    work_crc<=crc_next;crc_word<={crc_word[23:0],8'd0};
    write_phase<=write_phase==4 ? 0 : write_phase+1'b1;
   end
   case(state)
    IDLE:if(start && memory_ready)begin
     held_scene<=scene;held_size<=file_bytes;trusted[scene]<=0;fault<=0;error_code<=0;timer<=0;
     write_phase<=0;work_crc<=32'hffffffff;
     writer_start<=1;bmp_start<=1;state<=LOAD;
    end
    LOAD:begin
     if(werror)fail(8'h11);else if(!gen && bmp_fault)fail(bmp_error);
     else if(words_written==307200 && !wbusy && write_phase==0 &&
       (bmp_done && stream_done))begin
      if(!gen && (raw_bytes+54!=held_size || targets!=307200 || rows!={16'd0,sh} || fallback!=0 || dropped!=0))fail(8'h12);
      else begin
       read_pending<=0;reverse_pass<=0;read_index<=0;expected_write_crc<=work_crc;work_crc<=32'hffffffff;state<=READ;timer<=0;
      end
     end
    end
    READ:begin
     if(req_valid && req_ready)read_pending<=1;
     if(read_pending && rsp_valid)begin
      read_pending<=0;
      if(rsp_error)fail(8'h20);
      else begin crc_word<=rsp_data;read_phase<=0;state<=CRC;end
     end
    end
    CRC:begin
     work_crc<=crc_next;crc_word<={crc_word[23:0],8'd0};
     if(read_phase==3)begin
      if(read_index==307199)state<=VERIFY;
      else begin
       read_index<=read_index+1'b1;
       if(reverse_pass)begin
        if(read_x==639)begin read_x<=0;row_base<=row_base-640;end else read_x<=read_x+1'b1;
       end
       state<=READ;
      end
     end else read_phase<=read_phase+1'b1;
    end
    VERIFY:if(!reverse_pass)begin
     canonical_crc<=~work_crc;reverse_pass<=1;read_index<=0;row_base<=306560;read_x<=0;
     work_crc<=32'hffffffff;state<=READ;timer<=0;
    end else if(work_crc!=expected_write_crc)fail(8'h21);else state<=PUBLISH;
    PUBLISH:begin
     trusted[held_scene]<=1;
     source_crcs[held_scene*32 +:32]<=gen ? 0 : stream_crc;
     geometries[held_scene*32 +:32]<=gen ? {16'd640,16'd480} : {sw,sh};
     image_ready<=1;state<=IDLE;timer<=0;
    end
   endcase
   if(busy && timer>=TIMEOUT_CYCLES-1)fail(8'h30);
  end
 end
endmodule
