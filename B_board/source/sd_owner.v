`timescale 1ns/1ps
// Hold the selected owner to the end of the physical sector, including errors.
// Page changes cannot redirect pending responses or write data.
module sd_owner(
 input wire clk,rst_n,record_owner,
 input wire normal_request,input wire [31:0] normal_lba,
 output wire normal_accepted,normal_valid,normal_complete,normal_error,
 input wire record_request,input wire [31:0] record_lba,input wire record_write,
 output wire record_ready,record_accepted,record_valid,record_complete,record_error,
 output wire request,output wire [31:0] lba,output wire write_enable,
 input wire ready,accepted,valid,complete,error,output wire idle
);
 reg locked,selected;
 assign request=!locked && (record_owner ? record_request:normal_request);
 assign lba=record_owner ? record_lba:normal_lba;
 assign write_enable=record_owner && record_write;
 assign record_ready=!locked && ready;
 assign idle=!locked;
 assign normal_accepted=locked && !selected && accepted;
 assign normal_valid=locked && !selected && valid;
 assign normal_complete=locked && !selected && complete;
 assign normal_error=locked && !selected && error;
 assign record_accepted=locked && selected && accepted;
 assign record_valid=locked && selected && valid;
 assign record_complete=locked && selected && complete;
 assign record_error=locked && selected && error;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin locked<=0;selected<=0;end
  else begin
   if(request && ready)begin locked<=1;selected<=record_owner;end
   if(locked && (complete || error))locked<=0;
  end
endmodule
