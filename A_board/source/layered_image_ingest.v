`timescale 1ns/1ps
`include "atlas_contract.vh"
// Route ordinary pages through their existing loader and verification path.
module layered_image_ingest(
 input wire clk,rst_n,memory_ready,start,input wire [1:0] scene,
 input wire [31:0] file_bytes,input wire stream_valid,input wire [7:0] stream_data,
 output wire stream_ready,input wire stream_done,input wire [31:0] stream_crc,
 output wire busy,image_ready,output wire [3:0] trusted,
 output wire [31:0] display_crc,output wire [127:0] source_crcs,geometries,
 output wire fault,output wire [7:0] error_code,
 output wire req_valid,req_write,output wire [20:0] req_addr,output wire [31:0] req_data,
 input wire req_ready,rsp_valid,input wire [31:0] rsp_data,input wire rsp_error,
 output wire [31:0] words_written,max_wait,output wire [351:0] header_diagnostics,
 output wire [69:0] qualified_geometry,input wire atlas,output wire atlas_published
);
 wire nready,nbusy,ndone,nfault;wire [7:0] nerror;wire [31:0] ncrc,nwords;wire [69:0] ngeometry;
 wire nreq,nwrite;wire [20:0] naddr;wire [31:0] ndata;
 scene_image_ingest ordinary(clk,rst_n,memory_ready,start && !atlas,scene,file_bytes,stream_valid && !atlas,stream_data,nready,stream_done,stream_crc,
 nbusy,ndone,trusted,ncrc,source_crcs,geometries,nfault,nerror,nreq,nwrite,naddr,ndata,req_ready && !atlas,rsp_valid && !atlas,rsp_data,rsp_error,nwords,max_wait,header_diagnostics,ngeometry);
 wire aready,abusy,adone,afault;wire [7:0] aerror;wire [31:0] awords,adata;wire [20:0] aaddr;wire areq,awrite;
 atlas_ingest layered(clk,rst_n,start && atlas,memory_ready,scene,file_bytes,stream_valid && atlas,stream_data,aready,stream_done,stream_crc,
 abusy,adone,afault,aerror,areq,awrite,aaddr,adata,req_ready && atlas,rsp_valid && atlas,rsp_data,rsp_error,awords);
 assign atlas_published=adone;
 assign stream_ready=atlas ? aready:nready;
 assign busy=atlas ? abusy:nbusy;assign image_ready=atlas ? adone:ndone;
 assign fault=atlas ? afault:nfault;assign error_code=atlas ? aerror:nerror;
 assign req_valid=atlas ? areq:nreq;assign req_write=atlas ? awrite:nwrite;
 assign req_addr=atlas ? aaddr:naddr;assign req_data=atlas ? adata:ndata;
 assign words_written=atlas ? awords:nwords;assign display_crc=atlas ? `ATLAS_BASE_CRC:ncrc;
 assign qualified_geometry=atlas ? {16'd1280,16'd720,10'd640,9'd480,10'd0,9'd0}:ngeometry;
endmodule
