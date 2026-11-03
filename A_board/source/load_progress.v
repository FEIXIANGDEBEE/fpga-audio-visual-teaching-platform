`timescale 1ns/1ps
// Compare byte progress against ceil(k*total/8). Show it only for the
// accepted foreground transaction.
module load_progress(
 input wire clk,rst_n,active,input wire [31:0] epoch,received,total,
 output reg [3:0] segments
);
 reg [31:0] held_epoch;reg was_active;reg [35:0] threshold_eighths;
 // For integers, received>=ceil(te/8) iff 8*received>=te.
 // 8*received < 2^35; te <= 9*(2^32-1) < 2^36.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin segments<=0;held_epoch<=0;was_active<=0;threshold_eighths<=0;end
  else begin
   held_epoch<=epoch;was_active<=active;
   if(!active || !was_active || held_epoch!=epoch)begin segments<=0;threshold_eighths<={4'd0,total};end
   else if(total!=0 && segments<8 && {1'b0,received,3'b000}>=threshold_eighths)begin
    segments<=segments+1'b1;threshold_eighths<=threshold_eighths+{4'd0,total};
   end
  end
 end
endmodule
