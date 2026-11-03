`timescale 1ns/1ps
// Share one signed 28x24 MAC across separate L/R states and 63-tap histories.
// Publish each accepted frame after exactly LATENCY clocks.
module audio_fx #(parameter integer LATENCY=448)(
 input wire clk,rst_n,in_valid,input wire signed [15:0] in_left,in_right,
 input wire [1:0] mode,scene,input wire pause,mute,allow,
 output reg out_valid,output reg signed [15:0] out_left,out_right,
 output reg [1:0] active_mode,output reg [31:0] epoch,frames,clips,
 output reg warmup,metric_valid,output reg fault,output wire [1:0] active_scene,output wire in_ready
);
 localparam IDLE=0,START=1,NSET=2,NMUL=3,NACC=4,NROUND=5,STORE=6,FREAD=7,FMUL=8,FACC=9,FINISH=10,RAMPSET=11,RAMPMUL=12,RAMPEND=13,WAIT_SLOT=14;
 reg [3:0] state;reg [9:0] age;reg ch;reg [2:0] term;reg [5:0] tap,head;
 assign in_ready=state==IDLE;
 reg [6:0] history_valid;reg [8:0] warm_remaining;
 reg [1:0] old_scene;reg known_scene;
 assign active_scene=old_scene;
 reg pause_q,mute_q,allow_q;reg signed [15:0] raw_l,raw_r,notch_l,notch_r,result_l,result_r;
 reg signed [27:0] x1l,x2l,y1l,y2l,x1r,x2r,y1r,y2r;
 reg signed [27:0] mul_a;reg signed [23:0] mul_b;reg signed [51:0] product;
 reg signed [55:0] acc;
 (* ram_style="block" *) reg signed [15:0] history_l[0:63],history_r[0:63];
 reg signed [15:0] history_l_q,history_r_q;
 reg signed [17:0] coeff[0:62];initial $readmemh("fir_q17.hex",coeff);
 wire [5:0] address=head-tap;
 wire signed [15:0] hvalue=ch ? history_r_q:history_l_q;
 wire signed [27:0] fir_a=tap<history_valid ? {{12{hvalue[15]}},hvalue}:28'sd0;
 wire signed [23:0] fir_b={{6{coeff[tap][17]}},coeff[tap]};
 wire signed [27:0] operand_a=state==FMUL ? fir_a:mul_a;
 wire signed [23:0] operand_b=state==FMUL ? fir_b:mul_b;
 wire signed [55:0] total=acc+{{4{product[51]}},product};
 function signed [55:0] rounded;
  input signed [55:0] value;input integer bits;reg signed [55:0] bump;
  // Nearest rounding, ties away from zero: add half for positive values and
  // half-1 for negative values before the arithmetic shift.
  begin bump=56'sd1<<(bits-1);rounded=(value+(value<0 ? bump-56'sd1:bump))>>>bits;end
 endfunction
 function signed [15:0] limit16;
  input signed [55:0] value;
  begin limit16=value>32767 ? 16'sh7fff:value< -32768 ? 16'sh8000:value[15:0];end
 endfunction
 wire signed [55:0] nq=rounded(acc,22),fq=rounded(total,17),rq=rounded({{4{product[51]}},product},8);
 wire signed [15:0] raw_ch=ch ? raw_r:raw_l;
 always @(posedge clk)begin
  if(state==STORE)begin history_l[head]<=notch_l;history_r[head]<=notch_r;end
  history_l_q<=history_l[address];history_r_q<=history_r[address];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;age<=0;ch<=0;term<=0;tap<=0;head<=0;history_valid<=0;warm_remaining<=0;
   old_scene<=0;known_scene<=0;pause_q<=0;mute_q<=0;allow_q<=0;
   raw_l<=0;raw_r<=0;notch_l<=0;notch_r<=0;result_l<=0;result_r<=0;
   x1l<=0;x2l<=0;y1l<=0;y2l<=0;x1r<=0;x2r<=0;y1r<=0;y2r<=0;
   mul_a<=0;mul_b<=0;product<=0;acc<=0;out_valid<=0;out_left<=0;out_right<=0;
   active_mode<=0;epoch<=0;frames<=0;clips<=0;warmup<=0;metric_valid<=0;fault<=0;
  end else begin
   out_valid<=0;metric_valid<=0;
   if(state!=IDLE)age<=age+1'b1;
   if(in_valid && state!=IDLE)fault<=1;
   if(state==NMUL || state==FMUL || state==RAMPMUL)product<=operand_a*operand_b;
   case(state)
    IDLE:if(in_valid)begin
     raw_l<=in_left;raw_r<=in_right;pause_q<=pause;mute_q<=mute;allow_q<=allow;age<=0;ch<=0;term<=0;tap<=0;acc<=0;
     if(mode!=active_mode || !known_scene || scene!=old_scene || (!allow_q && allow))begin
      active_mode<=mode;epoch<=epoch+1'b1;old_scene<=scene;known_scene<=1;
      x1l<=0;x2l<=0;y1l<=0;y2l<=0;x1r<=0;x2r<=0;y1r<=0;y2r<=0;history_valid<=0;head<=0;
      warm_remaining<=mode!=0 ? 256:0;
     end else if(pause_q && !pause)begin
      // Keep filter history on resume. Start a measurement epoch that excludes
      // the 256-sample fade-in.
      epoch<=epoch+1'b1;warm_remaining<=256;
     end
     state<=START;
    end
    START:begin
     if(pause_q || !allow_q)begin result_l<=0;result_r<=0;state<=WAIT_SLOT;end
     else if(active_mode[0])state<=NSET;
     else begin notch_l<=raw_l;notch_r<=raw_r;state<=STORE;end
    end
    NSET:begin
     case(term)
      0:begin mul_a<=$signed(raw_ch)<<<8;mul_b<=24'sd4053465;end
      1:begin mul_a<=ch ? x1r:x1l;mul_b<=-24'sd7489826;end
      2:begin mul_a<=ch ? x2r:x2l;mul_b<=24'sd4053465;end
      3:begin mul_a<=ch ? y1r:y1l;mul_b<=24'sd7362560;end
      4:begin mul_a<=ch ? y2r:y2l;mul_b<=-24'sd3785359;end
     endcase
     state<=NMUL;
    end
    NMUL:state<=NACC;
    NACC:begin acc<=total;if(term==4)state<=NROUND;else begin term<=term+1'b1;state<=NSET;end end
    NROUND:begin
     if(nq>134217727 || nq< -134217728)fault<=1;
     if(rounded(nq,8)>32767 || rounded(nq,8)< -32768)clips<=clips+1'b1;
     if(!ch)begin
      x2l<=x1l;x1l<=$signed(raw_l)<<<8;y2l<=y1l;y1l<=nq[27:0];notch_l<=limit16(rounded(nq,8));
      ch<=1;term<=0;acc<=0;state<=NSET;
     end else begin
      x2r<=x1r;x1r<=$signed(raw_r)<<<8;y2r<=y1r;y1r<=nq[27:0];notch_r<=limit16(rounded(nq,8));state<=STORE;
     end
    end
    STORE:begin
     if(history_valid<63)history_valid<=history_valid+1'b1;
     ch<=0;tap<=0;acc<=0;
     if(active_mode[1])state<=FREAD;
     else begin result_l<=notch_l;result_r<=notch_r;state<=FINISH;end
    end
    FREAD:state<=FMUL;
    FMUL:state<=FACC;
    FACC:begin
     if(tap==62)begin
      if(fq>32767 || fq< -32768)clips<=clips+1'b1;
      if(!ch)begin result_l<=limit16(fq);ch<=1;tap<=0;acc<=0;state<=FREAD;end
      else begin result_r<=limit16(fq);state<=FINISH;end
     end else begin acc<=total;tap<=tap+1'b1;state<=FREAD;end
    end
    FINISH:begin
     head<=head+1'b1;ch<=0;
     if(warm_remaining!=0)state<=RAMPSET;else state<=WAIT_SLOT;
    end
    RAMPSET:begin mul_a<=ch ? result_r:result_l;mul_b<=24'sd256-$signed({1'b0,warm_remaining});state<=RAMPMUL;end
    RAMPMUL:state<=RAMPEND;
    RAMPEND:begin
     if(!ch)begin result_l<=limit16(rq);ch<=1;state<=RAMPSET;end
     else begin result_r<=limit16(rq);state<=WAIT_SLOT;end
    end
    WAIT_SLOT:;
    default:fault<=1;
   endcase
   if(state!=IDLE && age==LATENCY-1)begin
    if(state!=WAIT_SLOT)fault<=1;
    out_valid<=1;frames<=frames+1'b1;warmup<=warm_remaining!=0;
    out_left<=(!allow || pause || mute || fault || state!=WAIT_SLOT) ? 0:result_l;
    out_right<=(!allow || pause || mute || fault || state!=WAIT_SLOT) ? 0:result_r;
    metric_valid<=allow && !pause && !mute && !fault && state==WAIT_SLOT && warm_remaining==0;
    if(allow_q && !pause_q && !mute_q && warm_remaining!=0)warm_remaining<=warm_remaining-1'b1;
    state<=IDLE;
   end
  end
 end
endmodule
