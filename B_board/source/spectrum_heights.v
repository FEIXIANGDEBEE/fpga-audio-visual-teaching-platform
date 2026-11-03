// Convert power to amplitude height with radix-4 square root. All 16 bands
// finish within 273 clocks, before raster line 176 consumes the plot.
// Hold input bands until done; consume heights only after done.
module spectrum_heights(
 input clk,input rst_n,input start,input [15:0] power,
 output reg [127:0] heights,output reg busy,output reg done,output wire [3:0] power_address
);
 // Caller holds bands until done; results are consumed only after done.
 reg [3:0] band_index,step;
 reg loading;
 reg [15:0] radicand;
 reg [9:0] remainder;
 reg [7:0] root;
 reg saturated;
 wire [15:0] selected_power=power;
 assign power_address=!busy ? 4'd0:!loading && step==15 && band_index!=15 ? band_index+1'b1:band_index;
 wire [9:0] shifted_remainder={remainder[7:0],radicand[15:14]};
 wire [9:0] trial={root,2'b01};
 wire take=shifted_remainder>=trial;
 wire [7:0] next_root={root[6:0],take};
 wire [7:0] next_height=saturated ? 8'd240 : root;
 always @(posedge clk)begin
  if(!rst_n)begin heights<=0;busy<=0;done<=0;band_index<=0;step<=0;loading<=0;radicand<=0;remainder<=0;root<=0;saturated<=0;end
  else begin
   done<=0;
   if(start && !busy)begin band_index<=0;busy<=1;loading<=1;end
   else if(busy)begin
    if(loading)begin radicand<=selected_power[15:0];saturated<=selected_power>=21'd57600;remainder<=0;root<=0;step<=0;loading<=0;end
    else begin
     if(step<8)begin
      radicand<={radicand[13:0],2'b00};
      remainder<=take ? shifted_remainder-trial : shifted_remainder;
      root<=next_root;
     end
     if(step==15)begin
      heights[band_index*8+:8]<=next_height;
      if(band_index==15)begin busy<=0;done<=1;end
      else begin band_index<=band_index+1'b1;loading<=1;end
     end else step<=step+1'b1;
    end
   end
  end
 end
endmodule
