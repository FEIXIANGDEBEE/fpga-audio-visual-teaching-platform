`timescale 1ns/1ps
module tb;
 reg clk=0,rst=0,fv=0,right=0,ready=0,busy=0,done=0,rr=1,abort_capture=0;
 reg [31:0] frame=0,genin=1;reg[6:0]tag=7'h10;reg[2:0]ctx=0;
 always #10 clk=~clk;
 wire start,refstart,sv,rsv,rv,rrv,mixed,rmixed,out_right,rout_right;
 wire signed[15:0] sample,rsample;
 wire[31:0] window_id,rwindow,rgen,gen,base,rbase,crc,rcrc,actual,ractual,completed,rcompleted,dropped,rdropped,errors,rerrors,generation,rgeneration;
 wire[6:0]out_tag,rout_tag;wire[2:0]out_ctx,rout_ctx;
 scene_analysis_windows #(.V18_IDENTITY(1),.V22_SOURCE(1)) dut(
 .clk(clk),.rst_n(rst),.frame_valid(fv),.frame(frame),.select_right(right),.fft_start(start),.fft_window(window_id),.fft_sample_valid(sv),.fft_sample(sample),.fft_sample_ready(ready),.fft_busy(busy),.fft_done(done),.result_valid(rv),.result_ready(rr),.result_generation(gen),.result_base(base),.result_crc(crc),.result_right(out_right),.actual_frames(actual),.completed_windows(completed),.dropped_windows(dropped),.errors(errors),.generation(generation),.frame_tag(tag),.result_tag(out_tag),.result_mixed(mixed),.abort_capture(abort_capture),.frame_context(ctx),.frame_generation(genin),.result_context(out_ctx));
 windows_ref #(.V18_IDENTITY(1),.V22_SOURCE(1)) old(
 .clk(clk),.rst_n(rst),.frame_valid(fv),.frame(frame),.select_right(right),.fft_start(refstart),.fft_window(rwindow),.fft_sample_valid(rsv),.fft_sample(rsample),.fft_sample_ready(ready),.fft_busy(busy),.fft_done(done),.result_valid(rrv),.result_ready(rr),.result_generation(rgen),.result_base(rbase),.result_crc(rcrc),.result_right(rout_right),.actual_frames(ractual),.completed_windows(rcompleted),.dropped_windows(rdropped),.errors(rerrors),.generation(rgeneration),.frame_tag(tag),.result_tag(rout_tag),.result_mixed(rmixed),.abort_capture(abort_capture),.frame_context(ctx),.frame_generation(genin),.result_context(rout_ctx));
 integer cycles=0,taken=0,finish_delay=0,compared_samples=0,results=0,read0s=0,read1s=0,stalls=0,both=0;
 reg hold_engine=0;reg[15:0]before0,before1,mem0,mem1;reg read0_en,read1_en;
 always @(negedge clk)begin
  if(!rst)begin busy=0;ready=0;done=0;taken=0;finish_delay=0;end
  else begin
   cycles=cycles+1;ready=cycles%7<5;rr=cycles%11<7;
   if(done)begin done=0;busy=0;end
   if(start && !busy && !hold_engine)begin busy=1;taken=0;end
   if(hold_engine)busy=1;
   if(finish_delay>0)begin finish_delay=finish_delay-1;if(finish_delay==0)done=1;end
  end
 end
 always @(posedge clk)begin
  before0=dut.read0;before1=dut.read1;
  read0_en=dut.read_window && !dut.process_bank;read1_en=dut.read_window && dut.process_bank;
  if(rst && sv && ready)begin taken=taken+1;compared_samples=compared_samples+1;if(taken==512)finish_delay=12;end
  if(rst && sv && !ready)stalls=stalls+1;
  if(read0_en)read0s=read0s+1;if(read1_en)read1s=read1s+1;
  if(rst && (dut.status0==3 && dut.status1==1 || dut.status1==3 && dut.status0==1))both=both+1;
  if(rst && rv && rr)results=results+1;
  #1;
  if(!read0_en && dut.read0!==before0)$fatal(1,"unselected bank0 changed");
  if(!read1_en && dut.read1!==before1)$fatal(1,"unselected bank1 changed");
  if(rst)begin
   if({start,sv,rv,window_id,gen,base,crc,out_right,actual,completed,dropped,errors,generation,out_tag,mixed,out_ctx}!=={refstart,rsv,rrv,rwindow,rgen,rbase,rcrc,rout_right,ractual,rcompleted,rdropped,rerrors,rgeneration,rout_tag,rmixed,rout_ctx})$fatal(1,"window valid/counters/CRC/identity timing mismatch cycle=%0d phase=%0d",cycles,dut.phase);
   if(sv && sample!==rsample)$fatal(1,"sample mismatch cycle=%0d sample=%h ref=%h",cycles,sample,rsample);
   if(errors!=0)$fatal(1,"unexpected window CRC error %0d",errors);
  end
 end
 task tick;begin @(posedge clk);#3;end endtask
 task send_frames;input integer count,offset;integer i;begin
  for(i=0;i<count;i=i+1)begin
   @(negedge clk);#3;frame={16'(offset+i*97),16'(offset+i*313)};fv=1;tick;
   @(negedge clk);#3;fv=0;repeat(7)tick;
  end
 end endtask
 task sleep;begin
  @(negedge clk);#3;rst=0;fv=1;frame=32'hdeada123;
  mem0=dut.ram0[0];mem1=dut.ram1[0];repeat(8)tick;
  if(dut.ram0[0]!==mem0 || dut.ram1[0]!==mem1 || dut.read_window!==0)$fatal(1,"sleep RAM write/read not disabled");
  @(negedge clk);#3;fv=0;rst=1;hold_engine=0;repeat(5)tick;
 end endtask
 initial begin
  repeat(3)tick;sleep;
  send_frames(1536,10);repeat(7000)tick;
  right=1;ctx=4;genin=2;tag=7'h14;send_frames(1024,113);repeat(7000)tick;
  send_frames(23,901);@(negedge clk);#3;abort_capture=1;tick;@(negedge clk);#3;abort_capture=0;
  send_frames(512,2001);repeat(5000)tick;
  send_frames(53,3011);sleep;send_frames(512,4001);repeat(5000)tick;
  hold_engine=1;send_frames(1536,5001);hold_engine=0;busy=0;repeat(6000)tick;
  send_frames(512,6001);wait(dut.phase==3);sleep;send_frames(512,7001);repeat(5000)tick;
  if(compared_samples<3000 || results<6 || read0s==0 || read1s==0 || stalls==0 || both==0)$fatal(1,"insufficient coverage samples=%0d results=%0d reads=%0d/%0d stalls=%0d both=%0d",compared_samples,results,read0s,read1s,stalls,both);
  $display("WINDOWS_PASS samples=%0d results=%0d reads=%0d/%0d stalls=%0d concurrent=%0d CRC/cycle/identity exact, sleep no RAM reads/writes",compared_samples,results,read0s,read1s,stalls,both);$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
