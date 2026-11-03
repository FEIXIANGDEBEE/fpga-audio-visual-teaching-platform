`timescale 1ns/1ps
// Reserve distinct banks for capture, publication and the source snapshot.
// plot_snapshot changes its lock in vertical blank, when the old display bank
// can be reused without exposing writes to the raster.
module wave_store(
 input wire clk,rst_n,start,write_valid,input wire [4:0] write_index,
 input wire [6:0] write_data,input wire publish,clear,
 input wire [1:0] locked_bank,output wire [2:0] handle,
 input wire read_clk,input wire [6:0] read_address,output reg [6:0] read_data
);
 (* force_ram,ram_style="bram" *) reg [6:0] storage[0:127];
 reg [1:0] capture_bank,published_bank;reg zero;
 wire [1:0] free_bank=(published_bank!=0 && locked_bank!=0) ? 2'd0:
                       (published_bank!=1 && locked_bank!=1) ? 2'd1:2'd2;
 wire [1:0] write_bank=start ? free_bank:capture_bank;
 assign handle={zero,published_bank};
 always @(posedge clk)begin
  if(rst_n && write_valid)storage[{write_bank,write_index}]<=write_data;
 end
 always @(posedge read_clk)read_data<=storage[read_address];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin capture_bank<=0;published_bank<=1;zero<=1;end
  else begin
   if(start)capture_bank<=free_bank;
   if(clear)zero<=1;
   if(publish)begin published_bank<=capture_bank;zero<=0;end
  end
 end
endmodule
