`timescale 1ns/1ps
// Keep the W-advance contract even though the DSP product is ready earlier.
// FFT consumes product only after last; shortening this would change its schedule.
module dsp_multiply #(parameter W=28)(
 input wire clk,enable,load,advance,
 input wire signed [W-1:0] a,b,
 output reg signed [2*W-1:0] product,
 output wire last
);
 localparam CW=$clog2(W);
 // Isolate operand selection here; mapping may absorb these regs into DSPs
 reg signed [W-1:0] operand_a_q,operand_b_q;
 reg [CW-1:0] step;
 (* use_dsp="yes" *) wire signed [2*W-1:0] full_product=operand_a_q*operand_b_q;
 assign last=step==W-1;
 always @(posedge clk)if(enable)begin
  if(load)begin operand_a_q<=a;operand_b_q<=b;step<=0;end
  else if(advance)begin
   if(step==0)product<=full_product;
   if(!last)step<=step+1'b1;
  end
 end
endmodule
