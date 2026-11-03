`timescale 1ns/1ps
module tb;
 reg clk=0,rst=0,online=1,eligible=1,valid=0;reg[1:0] value=0;
 wire sleep,standby;integer i;
 always #10 clk=~clk;
 low_power_control dut(clk,rst,online,eligible,valid,value,sleep,standby);
 task tick;begin @(posedge clk);#1;end endtask
 task request;input[1:0] v;begin @(negedge clk);valid=1;value=v;tick;@(negedge clk);valid=0;end endtask
 initial begin
  tick;tick;rst=1;tick;
  request(3);if(!sleep || standby)$fatal(1,"reset must precede clock stop");
  repeat(4)tick;if(!standby)$fatal(1,"standby missing");
  repeat(30)tick;if(!sleep || !standby)$fatal(1,"sleep not retained");
  request(0);if(sleep)$fatal(1,"remote wake failed");repeat(4)tick;if(standby)$fatal(1,"standby did not clear");
  request(3);repeat(4)tick;@(negedge clk);eligible=0;tick;
  if(sleep)$fatal(1,"scene exit failed");repeat(4)tick;if(standby)$fatal(1,"scene standby stuck");
  request(3);if(sleep)$fatal(1,"ineligible accepted");
  @(negedge clk);eligible=1;request(3);repeat(4)tick;
  @(negedge clk);online=0;tick;if(sleep)$fatal(1,"offline recovery failed");
  @(negedge clk);online=1;repeat(6)tick;if(sleep || standby)$fatal(1,"auto reenter");
  for(i=0;i<4;i=i+1)begin request(3);request(2);repeat(6)tick;if(sleep || standby)$fatal(1,"rapid toggle stuck");end
  $display("LOW_POWER_CONTROL_PASS entry/exit/scene/offline/repeated/rapid");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
