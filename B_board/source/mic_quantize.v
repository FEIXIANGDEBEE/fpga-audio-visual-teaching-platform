`timescale 1ns/1ps
// Round to nearest, ties away from zero. A negative half-way remainder keeps
// the arithmetic floor; only a remainder above half increments it.
// Select fixed slices for the three shifts, then add the rounding bit once.
module mic_quantize(input wire signed [23:0] raw,input wire [1:0] gain,
 output reg signed [15:0] pcm,output reg clip);
 reg signed [19:0] quotient;
 reg increment;
 wire signed [20:0] rounded={quotient[19],quotient}+{20'd0,increment};
 always @*begin
  case(gain)
   2:begin quotient=raw[23:4];increment=raw[3] && (!raw[23] || |raw[2:0]);end
   1:begin quotient={{2{raw[23]}},raw[23:6]};increment=raw[5] && (!raw[23] || |raw[4:0]);end
   default:begin quotient={{4{raw[23]}},raw[23:8]};increment=raw[7] && (!raw[23] || |raw[6:0]);end
  endcase
  clip=rounded>21'sd32767 || rounded< -21'sd32768;
  pcm=rounded>21'sd32767 ? 16'sh7fff : rounded< -21'sd32768 ? 16'sh8000 : rounded[15:0];
 end
endmodule
