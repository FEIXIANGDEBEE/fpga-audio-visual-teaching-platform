`timescale 1ns/1ps
// C4-5-3F defaults: address 00; keys 0..16 are up/down/left/right/OK/*/#/0..9.
// UART [ starts a volatile table, ] enables it after 17 unique same-address frames,
// and } disables it. Reset restores the compiled map.
module ir_c453f_keymap(
 input wire clk,rst_n,frame_valid,input wire [7:0] address,command,
 input wire [7:0] uart_command,input wire uart_valid,
 output reg key_valid,output reg [4:0] key_id,
 output reg learning,enabled,output reg [4:0] learned,
 output reg [7:0] learned_address,output wire [7:0] selected_code,
 output reg rejected_learning
);
 // Entry i is DEFAULT_CODES[8*i+:8]; the low byte is the up key.
 localparam [135:0] DEFAULT_CODES={8'h09,8'h15,8'h07,8'h43,8'h40,8'h44,8'h47,8'h46,8'h45,
                                   8'h19,8'h0D,8'h16,8'h1C,8'h5A,8'h08,8'h52,8'h18};
 localparam [7:0] DEFAULT_ADDRESS=8'h00;
 reg [7:0] codes[0:16];integer i;reg duplicate,use_default;
 assign selected_code=learned<17 ? codes[learned]:8'd0;
 always @*begin
  duplicate=0;key_valid=0;key_id=0;
  for(i=0;i<17;i=i+1)begin
   if(i<learned && codes[i]==command)duplicate=1;
   if(enabled && learned==17 && address==learned_address &&
      (use_default ? DEFAULT_CODES[8*i+:8]==command : codes[i]==command))begin key_valid=1;key_id=i;end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin learning<=0;enabled<=1;learned<=17;learned_address<=DEFAULT_ADDRESS;use_default<=1;rejected_learning<=0;end
  else begin
   rejected_learning<=0;
   if(uart_valid && (uart_command=="[" || uart_command=="}"))begin
    learning<=uart_command=="[";enabled<=0;learned<=0;use_default<=0;
   end else if(uart_valid && uart_command=="]")begin
    if(learning && learned==17)begin learning<=0;enabled<=1;end else rejected_learning<=1;
   end else if(learning && frame_valid && learned<17)begin
    if((learned!=0 && address!=learned_address) || duplicate)rejected_learning<=1;
    else begin
     if(learned==0)learned_address<=address;
     codes[learned]<=command;learned<=learned+1'b1;
    end
   end
  end
 end
endmodule
