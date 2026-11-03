`timescale 1ns/1ps
`include "card_layout.vh"
// Discover 14 catalog slots, validate four WAVs with one parser, then arbitrate
// active/prepared/image bytes. The caller clears the selected FIFO in both
// clock domains before bind_valid.
module scene_wav_service #(parameter MAX_FILE_BYTES=2764854,
 parameter [447:0] EXTENT_LBAS=`CARD_LBAS,EXTENT_SIZES=`CARD_SIZES,EXTENT_CRCS=`CARD_CRCS)(
 input wire clk,rst_n,start,input wire [32:0] card_sectors,input wire boot_transfer_done,
 output wire sector_req,output wire [31:0] sector_lba,input wire sector_accepted,
 input wire [7:0] sector_data,input wire sector_valid,sector_end,sector_error,
 output wire initialized,volume_fault,output wire [7:0] volume_error,
 output wire [13:0] file_valid,file_rejected,output wire [3:0] wav_valid,wav_rejected,
 input wire active_bank,input wire [1:0] feed_enable,input wire [12:0] count0,count1,
 input wire bind_valid,bind_bank,input wire [1:0] bind_scene,
 output wire bind_ready,output reg bind_done,bind_error,
 output wire frame_valid,frame_bank,output wire [31:0] frame_data,input wire frame_ready,
 output wire [1:0] pcm_fault,output wire scheduler_fault,
 output wire [31:0] frames0,frames1,loops0,loops1,
 input wire image_demand,image_available,input wire [3:0] image_file,input wire [31:0] image_offset,
 output wire image_accepted,image_valid,image_error,output wire [7:0] image_data,
 input wire [1:0] descriptor_addr,output wire [96:0] descriptor,
 output wire [31:0] served0,served1,served2,output wire [1:0] context_quiescent,
 input wire [3:0] file_descriptor_addr,output wire [63:0] file_descriptor,
 output reg [63:0] bound_lengths,output wire ui_scan_done
);
 wire open_done,scan_done;assign ui_scan_done=scan_done;wire [31:0] unused_bytes;
 wire req,ready,bvalid,berror;wire [31:0] off;wire [1:0] owner,response_owner;wire [3:0] file_id,ca;
 wire [63:0] catalog_data;wire [7:0] bd;wire catalog_done;
 wire [3:0] file_catalog_addr=catalog_done ? file_descriptor_addr : ca;
 assign file_descriptor=catalog_data;
 scene_file_service #(.EXTENT_LBAS(EXTENT_LBAS),.EXTENT_SIZES(EXTENT_SIZES),.EXTENT_CRCS(EXTENT_CRCS)) files(clk,rst_n,start,card_sectors,boot_transfer_done,scan_done,open_done,volume_fault,volume_error,unused_bytes,
  req,off,owner,file_id,ready,berror,response_owner,file_catalog_addr,catalog_data,file_valid,file_rejected,
  bvalid,bd,sector_req,sector_lba,sector_accepted,sector_data,sector_valid,sector_end,sector_error);
 reg catalog_started,catalog_start;
 wire hreq;wire [31:0] hoff;wire [3:0] hfile;wire [7:0] header_error;
 reg [2:0] bind_state;reg [1:0] saved_scene;reg saved_bank;
 wire [1:0] read_scene=bind_state!=0 ? saved_scene : descriptor_addr;
 wire [96:0] metadata;
 scene_wav_catalog #(.MAX_FILE_BYTES(MAX_FILE_BYTES)) catalog(clk,rst_n,catalog_start,file_valid,ca,catalog_data,hreq,hoff,hfile,
  ready,bvalid && !catalog_done,berror && !catalog_done,bd,catalog_done,wav_valid,wav_rejected,
  read_scene,metadata,header_error);
 assign descriptor=metadata;
 assign initialized=catalog_done && !volume_fault;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin catalog_started<=0;catalog_start<=0;end
  else begin
   catalog_start<=0;
   if(scan_done && !catalog_started)begin catalog_start<=1;catalog_started<=1;end
  end
 end
 wire [1:0] demand,available,bound;wire [31:0] off0,off1;wire [3:0] f0,f1;
 wire aa,ab,av,ae,rb,pbind_ready,pbind_done;wire [7:0] pack_error;
 wire pack_bind=bind_state==3;
 scene_wav_packer #(.MAX_FILE_BYTES(MAX_FILE_BYTES)) packer(clk,rst_n,pack_bind,saved_bank,saved_scene,metadata,pbind_ready,pbind_done,
  feed_enable,count0,count1,demand,available,off0,off1,f0,f1,aa,ab,av,ae,rb,bd,
  frame_valid,frame_bank,frame_data,frame_ready,bound,pcm_fault,pack_error,frames0,frames1,loops0,loops1);
 // The packer reports global quiescence conservatively. Disable destination
 // demand before clear/bind so active-bank bytes cannot enter that destination.
 assign context_quiescent={2{pbind_ready}};
 assign bind_ready=initialized && bind_state==0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin bind_state<=0;saved_scene<=0;saved_bank<=0;bind_done<=0;bind_error<=0;bound_lengths<=0;end
  else begin
   bind_done<=0;bind_error<=0;
   case(bind_state)
    0:if(bind_valid && bind_ready)begin
     if(!wav_valid[bind_scene])begin bind_done<=1;bind_error<=1;end
     else begin saved_scene<=bind_scene;saved_bank<=bind_bank;bind_state<=1;end
    end
    1:bind_state<=2;
    2:if(pbind_ready)bind_state<=3;
    3:if(pbind_ready)begin bind_state<=4;bound_lengths[saved_bank*32 +:32]<=metadata[95:64];end
    4:if(pbind_done)begin bind_state<=0;bind_done<=1;bind_error<=pcm_fault[saved_bank];end
   endcase
  end
 end
 wire sreq;wire [1:0] so;wire [31:0] soff;wire [3:0] sf;
 wire boot_image_phase=file_valid[0] && !scan_done;
 scene_file_scheduler scheduler(clk,rst_n && (initialized || boot_image_phase),active_bank,
  {image_demand,initialized ? demand : 2'b00},{image_available,available},off0,off1,image_offset,f0,f1,image_file,
  sreq,so,soff,sf,ready,bvalid && (initialized || boot_image_phase),berror && (initialized || boot_image_phase),response_owner,
  aa,ab,image_accepted,av,ae,rb,image_valid,image_error,scheduler_fault,served0,served1,served2);
 assign req=(catalog_done || boot_image_phase) ? sreq : hreq;
 assign owner=(catalog_done || boot_image_phase) ? so : 2'd0;
 assign off=(catalog_done || boot_image_phase) ? soff : hoff;
 assign file_id=(catalog_done || boot_image_phase) ? sf : hfile;
 assign image_data=bd;
endmodule
