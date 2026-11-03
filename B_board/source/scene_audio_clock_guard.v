`timescale 1ns/1ps
// A supplies MCLK. A stalled clock asynchronously clears FIFO pointers in both
// domains and the serial pads. Keep restart latched until SYS explicitly
// recovers ownership and prepares a new epoch.
module scene_audio_clock_guard #(parameter TIMEOUT=4096,START_TICKS=4)(
 input wire sys_clk,sys_rst_n,mclk,run,recover,
 output wire audio_reset_n,output wire write_reset_n,
 output reg clock_alive,clock_fault,output reg [31:0] fault_events
);
 reg [4:0] divider;
 (* ASYNC_REG="TRUE" *) reg hb1,hb2;
 reg hb_seen;
 reg [15:0] wait_count;
 reg [3:0] start_count;
 reg allow;
 wire heartbeat_rst_n;
 reset_sync heartbeat_reset(mclk,sys_rst_n,heartbeat_rst_n);
 always @(posedge mclk or negedge heartbeat_rst_n)
  if(!heartbeat_rst_n)divider<=0;else divider<=divider+1'b1;
 wire reset_source=sys_rst_n && allow && !clock_fault;
 reset_sync ar(mclk,reset_source,audio_reset_n);
 reset_sync wr(sys_clk,reset_source,write_reset_n);
 always @(posedge sys_clk or negedge sys_rst_n)begin
  if(!sys_rst_n)begin
   hb1<=0;hb2<=0;hb_seen<=0;wait_count<=0;start_count<=0;
   clock_alive<=0;clock_fault<=0;fault_events<=0;allow<=0;
  end else begin
   hb1<=divider[4];hb2<=hb1;
   if(hb2!=hb_seen)begin
    hb_seen<=hb2;wait_count<=0;
    if(start_count<START_TICKS)start_count<=start_count+1'b1;
    if(start_count==START_TICKS-1)clock_alive<=1;
   end else if(wait_count<TIMEOUT)wait_count<=wait_count+1'b1;
   if(wait_count==TIMEOUT-1)begin
    clock_alive<=0;start_count<=0;allow<=0;
    if(run && !clock_fault)begin clock_fault<=1;fault_events<=fault_events+1'b1;end
   end
   if(!run)allow<=0;
   else if(clock_alive && !clock_fault)allow<=1;
   if(recover && clock_alive)begin clock_fault<=0;allow<=0;end
  end
 end
endmodule
