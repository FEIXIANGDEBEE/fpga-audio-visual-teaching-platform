`timescale 1ns/1ps

module scene_link(
 input wire clk,rst_n,
 input wire [7:0] in_data,input wire in_clk,in_valid,output wire in_ready,
 output wire [7:0] out_data,output wire out_clk,out_valid,input wire out_ready,
 input wire tx_valid,output wire tx_ready,tx_done,input wire [7:0] tx_type,tx_id,tx_flags,
 input wire [31:0] tx_epoch,tx_offset,input wire [9:0] tx_length,
 output wire [8:0] tx_addr,input wire [7:0] tx_data,
 output wire rx_valid,input wire rx_ready,output wire [7:0] rx_type,rx_id,rx_flags,
 output wire [31:0] rx_epoch,rx_offset,output wire [9:0] rx_length,
 input wire [8:0] rx_addr,output wire [7:0] rx_data,
 output wire [31:0] packets,crc_errors,format_errors,timeouts,tx_timeouts
);
 wire [7:0] rb,tb;wire rv,rr,tv,tr;wire [31:0] parser_timeouts;
 link_byte_rx receiver(clk,rst_n,1'b0,8'd0,1'b0,in_data,in_clk,in_valid,in_ready,rb,rv,rr,,);
 scene_packet_rx parser(clk,rst_n,rb,rv,rr,rx_valid,rx_ready,rx_type,rx_id,rx_flags,rx_epoch,rx_offset,rx_length,
  rx_addr,rx_data,packets,crc_errors,format_errors,parser_timeouts);
 scene_packet_tx sender(clk,rst_n,tx_valid,tx_type,tx_id,tx_flags,tx_epoch,tx_offset,tx_length,
  tx_ready,tx_done,,tx_addr,tx_data,tb,tv,tr);
 link_byte_tx transmitter(clk,rst_n,1'b0,tb,tv,tr,,out_data,out_clk,out_valid,out_ready,,tx_timeouts);
 assign timeouts=parser_timeouts;
endmodule
