`timescale 1ns/1ps
// Publish each configured extent after its full-file CRC32 passes; the catalog has 14 slots.
// Publish cached sectors only after physical-sector CRC16 passes.
module scene_file_service #(
 parameter [447:0] EXTENT_LBAS=256'h00007a1000007378000064d00000533800003e1c00002900000021f400002030,
 parameter [447:0] EXTENT_SIZES=256'h0017702c000d2f2c001d4c2c0023282c002a3036002a3036000e103600038436,
 parameter [447:0] EXTENT_CRCS=256'h961dde5d99afa9b556a985018da2e45176e7028316bc220f14dca113d601f35f
)(
 input wire clk,rst_n,start,input wire [32:0] card_sectors,
 input wire boot_transfer_done,output reg scan_done,
 output reg open_done,error,output reg [7:0] error_code,output reg [31:0] file_bytes,
 input wire byte_req,input wire [31:0] byte_offset,input wire [1:0] byte_owner,input wire [3:0] byte_file,
 output wire byte_ready,output reg byte_error,output reg [1:0] response_owner,
 input wire [3:0] catalog_addr,output reg [63:0] catalog_data,output reg [13:0] catalog_valid,catalog_rejected,
 output reg byte_valid,output reg [7:0] byte_data,
 output wire sector_req,output wire [31:0] sector_lba,input wire sector_accepted,
 input wire [7:0] sector_data,input wire sector_valid,sector_end,sector_error
);
 // Size internal addresses across all 14 extent slots, including simulation parameters.
 // Check full-width requests before truncating high bits.
 function [31:0] largest_size;
  input [447:0] sizes;integer j;reg [31:0] v;
  begin v=0;for(j=0;j<14;j=j+1)if(sizes[j*32+:32]>v)v=sizes[j*32+:32];largest_size=v;end
 endfunction
 function [32:0] largest_end;
  input [447:0] lbas,sizes;integer j;reg [32:0] v,e;
  begin v=0;for(j=0;j<14;j=j+1)begin
   e={1'b0,lbas[j*32+:32]}+(({1'b0,sizes[j*32+:32]}+33'd511)>>9);
   if(e>v)v=e;
  end largest_end=v;end
 endfunction
 function integer bits_needed;
  input [32:0] v;integer j;
  begin bits_needed=1;for(j=0;j<33;j=j+1)if(v[j])bits_needed=j+1;end
 endfunction
 localparam FILE_W=bits_needed({1'b0,largest_size(EXTENT_SIZES)});
 localparam END_W=bits_needed(largest_end(EXTENT_LBAS,EXTENT_SIZES)-1'b1);
 localparam LBA_W=END_W>32 ? 32 : END_W;
 localparam IDLE=0,INIT=1,FETCH=2,FILL=3,CHECK=4,NEXT=5,OPEN=6,RAM_WAIT=7,DELIVER=8,FAILED=9,ADDRESS=10,CLIENT_CHECK=11;
 reg [3:0] state;reg [3:0] catalog_index;
 // Keep one tagged sector per owner. The single outstanding request owns
 // the RAM port; audio refill must preserve the image owner's partial sector.
 (* ram_style="block" *) reg [7:0] cache[0:2047];
 reg [10:0] ram_addr;reg [7:0] ram_q;reg [9:0] fill_count;
 reg [2:0] cache_valid;reg [LBA_W-1:0] cache_lba[0:2];
 reg [LBA_W-1:0] sector_address;reg [FILE_W-1:0] remaining;reg [31:0] crc;
 wire [1:0] cache_owner=verifying ? 2'd2 : owner;
 reg [LBA_W-1:0] requested_lba;reg [8:0] requested_byte;reg [1:0] owner;
 reg [3:0] requested_file;reg [FILE_W-1:0] requested_offset;reg offset_high;
 reg verifying,boot_pause;
 function [461:0] extent_ends;
  input [447:0] lbas,sizes;integer i;
  begin for(i=0;i<14;i=i+1)extent_ends[i*33+:33]={1'b0,lbas[i*32+:32]}+(({1'b0,sizes[i*32+:32]}+33'd511)>>9);end
 endfunction
 localparam [461:0] ENDS=extent_ends(EXTENT_LBAS,EXTENT_SIZES);
 wire [3:0] lookup_index=verifying ? catalog_index:requested_file;
 wire [31:0] entry_lba=EXTENT_LBAS[lookup_index*32+:32];
 wire [31:0] entry_size=EXTENT_SIZES[lookup_index*32+:32];
 wire [31:0] entry_crc=EXTENT_CRCS[catalog_index*32+:32];
 wire [32:0] entry_end=ENDS[catalog_index*33+:33];
 wire [31:0] client_size=entry_size;
 wire [LBA_W:0] client_lba={1'b0,entry_lba[LBA_W-1:0]}+(requested_offset>>9);
 assign sector_lba=sector_address;
 assign byte_ready=state==OPEN && open_done && !error;
 assign sector_req=state==FETCH;
 function [31:0] crc_byte;
  input [31:0] prior;input [7:0] value;integer k;reg [31:0] c;
  begin c=prior^{24'd0,value};for(k=0;k<8;k=k+1)c=c[0] ? (c>>1)^32'hedb88320 : c>>1;crc_byte=c;end
 endfunction
 always @(posedge clk)begin
  if(state==FILL && sector_valid && fill_count<512)cache[{cache_owner,fill_count[8:0]}]<=sector_data;
  ram_q<=cache[ram_addr];
  catalog_data<=catalog_addr<14 ? {EXTENT_SIZES[catalog_addr*32+:32],EXTENT_LBAS[catalog_addr*32+:32]} : 64'd0;
 end
 task fail;input [7:0] code;
  begin error<=1;error_code<=code;open_done<=0;cache_valid<=0;state<=FAILED;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;catalog_index<=0;ram_addr<=0;fill_count<=0;cache_valid<=0;
   cache_lba[0]<=0;cache_lba[1]<=0;cache_lba[2]<=0;
   remaining<=0;crc<=32'hffffffff;requested_lba<=0;requested_byte<=0;owner<=0;verifying<=0;requested_file<=0;requested_offset<=0;offset_high<=0;
   open_done<=0;scan_done<=0;boot_pause<=0;error<=0;error_code<=0;file_bytes<=0;byte_error<=0;response_owner<=0;
   catalog_valid<=0;catalog_rejected<=0;byte_valid<=0;byte_data<=0;sector_address<=0;
  end else begin
   byte_valid<=0;byte_error<=0;
   if(sector_error)fail(8'h10);
   else case(state)
    IDLE:if(start)begin catalog_index<=0;catalog_valid<=0;catalog_rejected<=0;scan_done<=0;boot_pause<=0;verifying<=1;state<=INIT;end
    INIT:begin
     file_bytes<=entry_size;remaining<=entry_size;crc<=32'hffffffff;cache_valid[2]<=0;
     if(entry_size==0 || entry_size>67108864 || entry_end>card_sectors)begin
      catalog_rejected[catalog_index]<=1;state<=NEXT;
     end else begin sector_address<=entry_lba[LBA_W-1:0];state<=FETCH;end
    end
    FETCH:if(sector_accepted)begin fill_count<=0;cache_valid[cache_owner]<=0;state<=FILL;end
    FILL:begin
     if(sector_valid)begin
      if(fill_count==512)fail(8'h13);
      else begin
       fill_count<=fill_count+1'b1;
       if(verifying && fill_count<remaining)crc<=crc_byte(crc,sector_data);
      end
     end
     if(sector_end)begin
      if({1'b0,fill_count}+sector_valid!=512)fail(8'h12);
      else begin cache_valid[cache_owner]<=1;cache_lba[cache_owner]<=sector_address;state<=CHECK;end
     end
    end
    CHECK:if(verifying)begin
     if(remaining>512)begin remaining<=remaining-512;sector_address<=sector_address+1'b1;state<=FETCH;end
     else begin
      if((crc^32'hffffffff)==entry_crc)catalog_valid[catalog_index]<=1;
      else catalog_rejected[catalog_index]<=1;
      state<=NEXT;
     end
    end else begin ram_addr<={owner,requested_byte};state<=RAM_WAIT;end
    NEXT:if(catalog_index==13)begin open_done<=1;scan_done<=1;verifying<=0;state<=OPEN;end
     else if(catalog_index==0 && catalog_valid[0])begin
      // Give the verified first extent exclusive byte-channel use.
      // Resume the full-file scan after that transfer drains.
      catalog_index<=1;verifying<=0;boot_pause<=1;open_done<=1;state<=OPEN;
     end else begin catalog_index<=catalog_index+1'b1;state<=INIT;end
    OPEN:if(boot_pause && boot_transfer_done && !byte_req)begin
     boot_pause<=0;open_done<=0;verifying<=1;state<=INIT;
    end else if(byte_req)begin
     response_owner<=byte_owner;owner<=byte_owner;
     requested_file<=byte_file;requested_offset<=byte_offset;offset_high<=(byte_offset>>FILE_W)!=0;
     requested_byte<=byte_offset[8:0];state<=CLIENT_CHECK;
    end
    CLIENT_CHECK:begin
     if(owner>2 || requested_file>=14 || !catalog_valid[requested_file] || offset_high || requested_offset>=client_size || client_lba>=card_sectors)begin byte_error<=1;state<=OPEN;end
     // Check the full-width LBA here, before truncation; no extra per-byte address
     // state is needed. Complete sector CRC still gates cache publication.
     else if(cache_valid[owner] && {1'b0,cache_lba[owner]}==client_lba)begin ram_addr<={owner,requested_byte};state<=RAM_WAIT;end
     else begin sector_address<=client_lba[LBA_W-1:0];state<=FETCH;end
    end
    ADDRESS:if(cache_valid[owner] && cache_lba[owner]==requested_lba)begin ram_addr<={owner,requested_byte};state<=RAM_WAIT;end
     else begin sector_address<=requested_lba;state<=FETCH;end
    RAM_WAIT:state<=DELIVER;
    DELIVER:begin byte_data<=ram_q;byte_valid<=1;response_owner<=owner;state<=OPEN;end
    FAILED:begin error<=1;open_done<=0;end
    default:fail(8'h1f);
   endcase
  end
 end
endmodule
