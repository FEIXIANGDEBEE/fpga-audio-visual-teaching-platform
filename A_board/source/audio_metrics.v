`timescale 1ns/1ps
// Project left PCM onto the 3 kHz I/Q reference before and after filtering.
// This calculation is independent of the filter MAC. low_pre/low_post stay zero;
// completed high_pre/high_post values carry block_id and record_valid.
module audio_metrics(
 input wire clk,rst_n,sample_valid,eligible,
 input wire signed [15:0] pre,post,input wire [31:0] epoch,
 output reg record_valid,output reg [15:0] block_id,
 output reg [31:0] low_pre,low_post,high_pre,high_post,
 output reg fault
);
 localparam IDLE=0,READ=1,MUL=2,ADD=3,PREAD=4,PMUL=5,PADD=6;
 // op={post,quadrature}: pre I, pre Q, post I, post Q.
 reg [2:0] state;reg [1:0] op;reg band;reg component;
 reg [9:0] count;reg [7:0] phase;reg [31:0] current_epoch;
 reg signed [15:0] pre_q,post_q;
 wire [1:0] power_i={band,1'b0};
 wire [1:0] power_q={band,1'b1};
 (* ram_style="distributed" *) reg signed [42:0] iq[0:3];
 reg [3:0] iq_valid;
 reg signed [42:0] iq_read;
 wire [1:0] next_power_i=band ? 2'd0 : 2'd2;
 // Present each RAM address in the state before its operand is used.
 wire [1:0] iq_addr=state==PADD ? (component ? next_power_i:power_q) :
  state==ADD && op==3 && count==1023 ? 2'd0 :
  state==PREAD || state==PMUL ? (component ? power_q:power_i) : op;
 wire signed [42:0] accumulation=iq_valid[op] ? iq_read:43'sd0;
 wire signed [42:0] power_value=iq_valid[component ? power_q:power_i] ? iq_read:43'sd0;
 wire clear_block=epoch!=current_epoch || (sample_valid && !eligible);
 (* ram_style="block" *) reg signed [15:0] sine[0:255];initial $readmemh("sin_q15.hex",sine);
 reg signed [15:0] sine_q;
 wire [7:0] address={phase[3:0],4'b0}+(op[0] ? 8'd0:8'd64);
 reg signed [17:0] power_operand;
 wire signed [17:0] ma=state==PMUL ? power_operand:op[1] ? {{2{post_q[15]}},post_q}:{{2{pre_q[15]}},pre_q};
 wire signed [17:0] mb=state==PMUL ? power_operand:{{2{sine_q[15]}},sine_q};
 reg signed [35:0] product;reg [36:0] first_power;
 wire [36:0] power_sum=first_power+{1'b0,product};
 wire [31:0] bounded_power=|power_sum[36:32] ? 32'hffffffff:power_sum[31:0];
 always @(posedge clk)begin
  sine_q<=sine[address];
  iq_read<=iq[iq_addr];
  if(rst_n && !clear_block && state==ADD)
   iq[op]<=accumulation+{{7{product[35]}},product};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;op<=0;band<=0;component<=0;count<=0;phase<=0;current_epoch<=0;pre_q<=0;post_q<=0;
   iq_valid<=0;
   record_valid<=0;block_id<=0;low_pre<=0;low_post<=0;high_pre<=0;high_post<=0;fault<=0;power_operand<=0;product<=0;first_power<=0;
  end else begin
   if(state==MUL || state==PMUL)product<=ma*mb;
   if(epoch!=current_epoch)begin
    current_epoch<=epoch;record_valid<=0;count<=0;phase<=0;state<=IDLE;
    iq_valid<=0;
   end else if(sample_valid && !eligible)begin
    // Keep the last complete record through pause/HOLD; discard the partial block.
    count<=0;phase<=0;state<=IDLE;iq_valid<=0;
   end else begin
    if(sample_valid && eligible && state!=IDLE)fault<=1;
    case(state)
     IDLE:if(sample_valid && eligible)begin pre_q<=pre;post_q<=post;op<=0;state<=READ;end
     READ:state<=MUL;
     MUL:state<=ADD;
     ADD:begin
      iq_valid[op]<=1;
      if(op!=3)begin op<=op+1'b1;state<=READ;end
      else if(count==1023)begin band<=0;component<=0;state<=PREAD;end
      else begin count<=count+1'b1;phase<=phase+1'b1;state<=IDLE;end
     end
     PREAD:begin power_operand<=$signed(power_value)>>>23;state<=PMUL;end
     PMUL:state<=PADD;
     PADD:begin
      if(!component)begin first_power<={1'b0,product};component<=1;state<=PREAD;end
      else begin
       if(band)high_post<=bounded_power;else high_pre<=bounded_power;
       if(!band)begin band<=1;component<=0;state<=PREAD;end
       else begin
        record_valid<=1;block_id<=block_id+1'b1;count<=0;phase<=phase+1'b1;state<=IDLE;
        iq_valid<=0;
       end
      end
     end
     default:begin fault<=1;state<=IDLE;end
    endcase
   end
  end
 end
endmodule
