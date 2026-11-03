`timescale 1ns/1ps
module tb;
 reg clk=0,rst=0,start=0,sv=0;reg signed[15:0] sample=0;reg[1:0] weight=0;reg[31:0] wid=0;
 wire ready,refready,busy,refbusy,done,refdone,bv,rbv,bl,rbl;wire[3:0] bi,rbi;
 wire[31:0] energy,re,window_id,rw,lat,rl,errors,rerr,sat,rsat,mag,rmag;wire[8:0] peak,rpeak;
 integer i,j,bands=0,cycles=0;
 always #10 clk=~clk;
 fft_spectrum dut(clk,rst,start,wid,sv,ready,sample,busy,done,window_id,bv,bi,energy,bl,lat,1'b1,peak,mag,sat,errors,weight);
 fft_spectrum_ref refdut(clk,rst,start,wid,sv,refready,sample,refbusy,refdone,rw,rbv,rbi,re,rbl,rl,1'b1,rpeak,rmag,rsat,rerr,weight);
 always @(negedge clk)if(rst)begin
  if({ready,busy,done,bv,bl}!=={refready,refbusy,refdone,rbv,rbl})$fatal(1,"cycle/control mismatch");
  if(bv)begin if({bi,energy,window_id}!=={rbi,re,rw})$fatal(1,"spectrum mismatch");bands=bands+1;end
  if(done && {lat,errors,sat,peak,mag}!=={rl,rerr,rsat,rpeak,rmag})$fatal(1,"diagnostics mismatch");
 end
 task tick;begin @(posedge clk);#1;end endtask
 task reset_sleep;begin
  @(negedge clk);#2;rst=0;sv=0;start=0;repeat(8)tick;
  if(dut.g_coefficients.coefficient_rom.cea!==0 || dut.g_coefficients.coefficient_rom.ceb!==0 || dut.real_ram.read_enable!==0 || dut.imag_ram.read_enable!==0)$fatal(1,"sleep read clock enable active");
  if(busy || bv)$fatal(1,"analysis active in sleep");
  @(negedge clk);#2;rst=1;repeat(4)tick;
 end endtask
 task begin_window;begin @(negedge clk);#2;wid=wid+1;start=1;tick;@(negedge clk);#2;start=0;end endtask
 task feed;input integer count;begin
  for(i=0;i<count;i=i+1)begin
   while(!ready)tick;
   @(negedge clk);#2;sample=((i*313+wid*37)%30000)-15000;sv=1;tick;
   @(negedge clk);#2;sv=0;
  end
 end endtask
 initial begin
  reset_sleep;
  begin_window;feed(17);reset_sleep;
  begin_window;feed(512);repeat(31)tick;reset_sleep;
  for(j=0;j<4;j=j+1)begin
   weight=j;begin_window;feed(512);cycles=0;
   while(!done)begin tick;cycles=cycles+1;if(cycles>500000)$fatal(1,"FFT timeout");end
   repeat(3)tick;
  end
  if(bands!=64)$fatal(1,"band coverage %0d",bands);
  $display("FFT_PASS 4 weight modes 64 bands cycle exact; sleep mid-capture/multiply; wake and CE disabled");$finish;
 end
 initial begin #50000000;$fatal(1,"overall timeout");end
endmodule
