`timescale 1ns/1ps
// Latch timeout/length faults until reset so late sector bytes cannot enter
// a subsequent file request.
module scene_sd_sector #(parameter SPI_LOW_SPEED_DIV=248,TIMEOUT_CYCLES=5000000,WRITE_TIMEOUT_CYCLES=12500000)(
 input wire clk,rst_n,
 output wire sd_ncs,sd_dclk,sd_mosi,input wire sd_miso,
 output wire init_done,output wire [32:0] card_sectors,output wire init_error,
 input wire request,input wire [31:0] lba,output wire ready,output reg accepted,
 output wire [7:0] data,output wire valid,output reg complete,error,
 output reg fault,output reg [7:0] fault_code,output reg [31:0] max_wait,
 output wire [191:0] init_diagnostics,
 input wire write_enable,input wire [7:0] write_data,output wire [8:0] write_address,output wire write_take
);
 wire pv,pe,block_crc_error;wire [7:0] pd;reg preq;reg [31:0] plba;
 reg busy,armed,busy_write;reg [9:0] count;reg [31:0] timer;
 wire pwreq,pwend,pwerror;
 scene_sd_card_top #(.SPI_LOW_SPEED_DIV(SPI_LOW_SPEED_DIV)) physical(
  .clk(clk),.rst(!rst_n),.SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso),
  .card_sectors(card_sectors),.init_error(init_error),.sd_init_done(init_done),.init_diagnostics(init_diagnostics),.block_crc_error(block_crc_error),
  .sd_sec_read(preq && !busy_write),.sd_sec_read_addr(plba),.sd_sec_read_data(pd),.sd_sec_read_data_valid(pv),.sd_sec_read_end(pe),
  .sd_sec_write(preq && busy_write),.sd_sec_write_addr(plba),.sd_sec_write_data(write_data),.sd_sec_write_data_req(pwreq),.sd_sec_write_end(pwend),.sd_sec_write_error(pwerror));
 assign ready=init_done && !busy && !fault;
 assign data=pd;assign valid=busy && !busy_write && !fault && pv && count<512;
 assign write_address=count[8:0];assign write_take=busy && busy_write && !fault && pwreq && count<512;
 wire event_byte=busy_write ? pwreq:pv;
 wire [10:0] final_count={1'b0,count}+event_byte;
 task fail;input [7:0] code;
  begin busy<=0;fault<=1;error<=1;fault_code<=code;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;busy_write<=0;armed<=1;count<=0;timer<=0;preq<=0;plba<=0;accepted<=0;complete<=0;error<=0;fault<=0;fault_code<=0;max_wait<=0;end
  else begin
   preq<=0;accepted<=0;complete<=0;error<=0;
   if(!request)armed<=1;
   if(init_error && !fault)fail(8'h10);
   else if(ready && request && armed)begin
    if({1'b0,lba}>=card_sectors)fail(8'h04);
    else begin busy<=1;busy_write<=write_enable;armed<=0;count<=0;timer<=0;preq<=1;plba<=lba;accepted<=1;end
   end
   if(busy && !fault)begin
    timer<=timer+1'b1;if(timer>max_wait)max_wait<=timer;
    if(event_byte && count==512)fail(8'h03);
    else if(busy_write ? pwend:pe)begin
     if(busy_write && pwerror)fail(8'h06);
     else if(!busy_write && block_crc_error)fail(8'h05);
     else if(final_count!=512)fail(8'h02);
     else begin busy<=0;complete<=1;end
    end else if(timer>=(busy_write ? WRITE_TIMEOUT_CYCLES:TIMEOUT_CYCLES)-1)fail(8'h01);
    else if(event_byte)count<=count+1'b1;
   end
  end
 end
endmodule
