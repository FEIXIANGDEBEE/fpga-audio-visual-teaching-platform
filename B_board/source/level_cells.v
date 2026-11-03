`timescale 1ns/1ps
// Five successive threshold decisions produce one 0..24 cell count.
module level_cells(input wire clk,rst_n,start,input wire [15:0] value,
 output reg [4:0] result,output reg done);
 reg busy;reg [15:0] held_value;reg [4:0] code,bit_mask;
 wire [4:0] trial=code|bit_mask;
 reg [15:0] threshold;
 always @(*)begin
  case(trial)
   1:threshold=164;2:threshold=207;3:threshold=260;4:threshold=328;
   5:threshold=413;6:threshold=519;7:threshold=654;8:threshold=823;
   9:threshold=1036;10:threshold=1305;11:threshold=1642;12:threshold=2068;
   13:threshold=2603;14:threshold=3277;15:threshold=4125;16:threshold=5193;
   17:threshold=6538;18:threshold=8231;19:threshold=10362;20:threshold=13045;
   21:threshold=16423;22:threshold=20675;23:threshold=26029;24:threshold=32760;
   default:threshold=16'hffff;
  endcase
 end
 wire [4:0] next_code=trial<=24 && held_value>=threshold ? trial:code;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;held_value<=0;code<=0;bit_mask<=0;result<=0;done<=0;end
  else begin
   done<=0;
   if(start && !busy)begin busy<=1;held_value<=value;code<=0;bit_mask<=16;end
   else if(busy)begin
    code<=next_code;bit_mask<=bit_mask>>1;
    if(bit_mask==1)begin result<=next_code;done<=1;busy<=0;end
   end
  end
 end
endmodule
