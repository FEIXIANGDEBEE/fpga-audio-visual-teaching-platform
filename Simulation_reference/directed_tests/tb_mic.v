`timescale 1ns/1ps
module tb;
 reg clk=0,mclk=0,rst=0,online=1,eligible=1,vv=0,mrun=1;reg[1:0]view=0;reg sd=0;
 always #10 clk=~clk;always #41 if(mrun)mclk=~mclk;
 wire sleep,standby,eco_rst;low_power_control control(clk,rst,online,eligible,vv,view,sleep,standby);
 reset_sync eco_reset(clk,rst && !sleep,eco_rst);
 wire sck,ws,valid,alive,warm,activity,rsck,rws,rvalid,ralive,rwarm,ractivity;
 wire[34:0]data,rdata;wire[31:0]overflow,events,roverflow,revents;
 mic_input #(.WARMUP_FRAMES(8),.CLOCK_TIMEOUT(8000)) dut(clk,eco_rst,mclk,sd,2'd1,sck,ws,valid,data,alive,warm,overflow,events,activity);
 mic_ref #(.WARMUP_FRAMES(8),.CLOCK_TIMEOUT(8000)) refdut(clk,eco_rst,mclk,sd,2'd1,rsck,rws,rvalid,rdata,ralive,rwarm,roverflow,revents,ractivity);
 reg[23:0] lfsr=24'h381195;integer sck_edges=0,packets=0,before_edges=0,before_packets=0,wakes=0;
 always @(negedge mclk)begin lfsr={lfsr[22:0],lfsr[23]^lfsr[22]^lfsr[17]^lfsr[4]};sd=lfsr[7];end
 always @(posedge sck)sck_edges=sck_edges+1;
 always @(posedge clk)begin #2;
  if({sck,ws,valid,alive,warm,activity,overflow,events}!=={rsck,rws,rvalid,ralive,rwarm,ractivity,roverflow,revents})$fatal(1,"normal microphone contract changed");
  if(valid)begin packets=packets+1;if(data!==rdata || !warm)$fatal(1,"mic sample/sequence before warm or mismatch");end
 end
 task tick;begin @(posedge clk);#4;end endtask
 task mode;input[1:0]v;begin @(negedge clk);#3;view=v;vv=1;tick;@(negedge clk);#3;vv=0;end endtask
 task wait_packets;input integer n;integer target,loops;begin target=packets+n;loops=0;while(packets<target)begin tick;loops=loops+1;if(loops>70000)$fatal(1,"MIC wake stalled");end wakes=wakes+1;end endtask
 task check_sleep;begin
  repeat(12)tick;before_edges=sck_edges;before_packets=packets;repeat(1000)tick;
  if(sck_edges!=before_edges || packets!=before_packets || alive || warm || valid || dut.divider!==0 || dut.samples.request!==0 || dut.samples.ack!==0)$fatal(1,"microphone activity during sleep");
 end endtask
 initial begin
  repeat(4)tick;@(negedge clk);#3;rst=1;wait_packets(4);
  mode(3);check_sleep;mode(0);if(warm)$fatal(1,"warmup bypassed");wait_packets(4);
  mode(3);check_sleep;eligible=0;wait_packets(4);eligible=1;
  mode(3);check_sleep;online=0;wait_packets(4);online=1;
  mode(3);check_sleep;mode(1);repeat(6)tick;mode(3);check_sleep;mode(2);wait_packets(4);
  @(negedge mclk);#3;mrun=0;repeat(8500)tick;if(alive)$fatal(1,"clock loss not detected");
  mrun=1;wait_packets(4);
  if(wakes!=6 || packets<24)$fatal(1,"coverage");
  $display("MIC_PASS normal sample contract exact; sleep/rapid wake/scene/offline/MCLK recovery; packets=%0d",packets);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
