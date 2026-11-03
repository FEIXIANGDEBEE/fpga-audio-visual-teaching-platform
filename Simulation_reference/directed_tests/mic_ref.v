`timescale 1ns/1ps
// Automatic MCLK recovery resets both mailbox endpoints together.
module mic_ref #(parameter CLOCK_TIMEOUT=50000,WARMUP_FRAMES=4096)(
 input wire clk,rst_n,mclk,mic_sd,input wire [1:0] requested_gain,
 output wire mic_sck,mic_ws,output wire valid,output wire [34:0] data,
 output reg clock_alive,output wire warmed,output wire [31:0] overflows,
 output reg [31:0] clock_events,output wire raw_activity);
 wire hb_reset;
 reset_sync heartbeat_reset(mclk,rst_n,hb_reset);
 reg [9:0] divider;
 always @(posedge mclk or negedge hb_reset)if(!hb_reset)divider<=0;else divider<=divider+1'b1;
 (* ASYNC_REG="TRUE" *) reg hb1,hb2;
 reg seen;reg [15:0] wait_count;reg [2:0] ticks;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin hb1<=0;hb2<=0;seen<=0;wait_count<=0;ticks<=0;clock_alive<=0;clock_events<=0;end
  else begin
   hb1<=divider[9];hb2<=hb1;
   if(hb2!=seen)begin seen<=hb2;wait_count<=0;if(ticks<4)ticks<=ticks+1'b1;if(ticks==3)clock_alive<=1;end
   else if(wait_count<CLOCK_TIMEOUT)wait_count<=wait_count+1'b1;
   if(wait_count==CLOCK_TIMEOUT-1)begin
    if(clock_alive)clock_events<=clock_events+1'b1;
    clock_alive<=0;ticks<=0;
   end
  end
 end
 wire shared_rst=rst_n && clock_alive;
 wire mrst,srst;
 reset_sync mic_reset(mclk,shared_rst,mrst);
 reset_sync mail_reset(clk,shared_rst,srst);
 wire gain_valid;wire [1:0] gain_snapshot;
 assign gain_snapshot=2'd1; // Resource-budget fallback: fixed x4, no gain CDC.
 wire rv;wire [23:0] raw;wire [15:0] seq;wire warm;
 mic_i2s_rx #(.WARMUP_FRAMES(WARMUP_FRAMES)) receiver(mclk,mrst,mic_sd,mic_sck,mic_ws,rv,raw,seq,warm);
 wire [15:0] pcm;wire clip;
 mic_quantize quantizer(raw,gain_snapshot,pcm,clip);
 wire ready;
 scene_cdc_mailbox #(.WIDTH(35)) samples(mclk,mrst,rv && ready,{seq,gain_snapshot,clip,pcm},ready,,clk,srst,valid,data,1'b1);
 reg [31:0] lost;wire [31:0] lost_sys;reg raw_active;
 always @(posedge mclk or negedge mrst)if(!mrst)raw_active<=0;else if(rv && raw!=0)raw_active<=1;
 always @(posedge mclk or negedge mrst)if(!mrst)lost<=0;else if(rv && !ready)lost<=lost+1'b1;
 cdc_snapshot #(.WIDTH(34)) diagnostics(mclk,mrst,{warm,raw_active,lost},clk,srst,1'b1,{warmed,raw_activity,lost_sys});
 assign overflows=lost_sys;
endmodule
