`timescale 1ns/1ps
// Capture four coherent diagnostic words per row in a 128-bit frame.
// Commands remain active during TX; a page change appears in the next captured row.
module scene_uart #(parameter BOARD=8'h42,DIV=434,PERIOD=50000000)(
 input wire clk,rst_n,uart_rx,output reg uart_tx,input wire [127:0] stats,
 input wire [7:0] page,output wire [7:0] command,output wire command_valid
);
 wire framing_error;
 uart_rx #(.CLKS_PER_BIT(DIV)) receiver(clk,rst_n,uart_rx,command,command_valid,framing_error);
 reg [127:0] held;reg [7:0] held_page;reg [25:0] timer;reg pending,active;
 reg [5:0] position;reg [9:0] bits;reg [8:0] baud;reg [3:0] bit_count;
 reg [7:0] character;reg [3:0] nibble;
 reg [1:0] word_index;reg [3:0] char_index;
 reg [31:0] selected_word;
 always @*begin
  case(word_index)
   0:selected_word=held[127:96];1:selected_word=held[95:64];
   2:selected_word=held[63:32];3:selected_word=held[31:0];
   default:selected_word=0;
  endcase
  case(char_index)
   0:nibble=selected_word[31:28];1:nibble=selected_word[27:24];
   2:nibble=selected_word[23:20];3:nibble=selected_word[19:16];
   4:nibble=selected_word[15:12];5:nibble=selected_word[11:8];
   6:nibble=selected_word[7:4];7:nibble=selected_word[3:0];
   default:nibble=0;
  endcase
  character=8'h20;
  case(position)
   0:character="V";1:character="1";2:character="4";3:character=BOARD;5:character=held_page;43:character=10;
   default:if(position>=7 && position<43)begin
    if(char_index<8)character=nibble<10 ? 48+nibble : 87+nibble;
   end
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin held<=0;held_page<="Q";timer<=0;pending<=1;active<=0;position<=0;word_index<=0;char_index<=0;bits<=1023;baud<=0;bit_count<=0;uart_tx<=1;end
  else begin
   if(timer==PERIOD-1)begin timer<=0;pending<=1;end else timer<=timer+1'b1;
   if(command_valid && command=="?")pending<=1;
   if(!active && pending)begin active<=1;pending<=0;held<=stats;held_page<=page;position<=0;word_index<=0;char_index<=0;bit_count<=0;end
   if(active)begin
    if(bit_count==0)begin bits<={1'b1,character,1'b0};baud<=DIV-1;bit_count<=10;uart_tx<=0;end
    else if(baud!=0)baud<=baud-1'b1;
    else begin
     baud<=DIV-1;bits<={1'b1,bits[9:1]};uart_tx<=bits[1];bit_count<=bit_count-1'b1;
     if(bit_count==1)begin
      if(position==43)begin active<=0;uart_tx<=1;end
      else begin
       position<=position+1'b1;
       if(position>=7 && position<43)begin
        if(char_index==8)begin char_index<=0;word_index<=word_index+1'b1;end
        else char_index<=char_index+1'b1;
       end
      end
     end
    end
   end
  end
 end
endmodule
