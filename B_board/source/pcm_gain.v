`timescale 1ns/1ps

module pcm_gain(input wire [31:0] frame,input wire [8:0] gain,output wire [31:0] scaled);
 wire signed [15:0] xl=frame[15:0],xr=frame[31:16];
 // gain=256 bypasses exactly; factors 0..255 use signed DSP products.
 // |x|*255+128 <= 8355968, so the rounded magnitude fits 16 bits.
 wire signed [8:0] factor=$signed({1'b0,gain[7:0]});
 (* use_dsp="yes" *)wire signed [24:0] pl=xl*factor,pr=xr*factor;
 // Bias negative products by 127 and positive products by 128 before /256.
 // This rounds symmetrically, with half-way values going away from zero.
 wire signed [24:0] bl=pl+(pl[24] ? 25'sd127:25'sd128);
 wire signed [24:0] br=pr+(pr[24] ? 25'sd127:25'sd128);
 assign scaled=gain[8] ? frame:{br[23:8],bl[23:8]};
endmodule
