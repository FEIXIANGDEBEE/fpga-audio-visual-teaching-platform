`timescale 1ns/1ps
// Hold all 16 band words through map_done. analysis does not publish another
// band_valid while the current rv/map_done exchange owns the mapper.
module power_heights(input wire clk,rst_n,band_valid,input wire [3:0] band_index,
 input wire [31:0] energy,input wire start,output wire [127:0] heights,output wire busy,done);
 wire [20:0] quantized_power=energy[31:11];
 wire [15:0] bounded_power=quantized_power>=21'd57600 ? 16'd57600:quantized_power[15:0];
 wire [15:0] power;wire [3:0] read_address;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(4),.ADDR_WIDTH_B(4),
 .DATA_DEPTH_A(16),.DATA_DEPTH_B(16),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
 .doa(),.dob(power),.dia(bounded_power),.dib(16'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),
 .clka(clk),.clkb(clk),.wea(band_valid),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
 .addra(band_index),.addrb(read_address));
 spectrum_heights conversion(clk,rst_n,start,power,heights,busy,done,read_address);
endmodule
