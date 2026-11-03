from pathlib import Path
import subprocess,json,time
R=Path(__file__).resolve().parents[1];P=R.parent/'V15_low_power'
O=Path('D:/aidownload/anlu_main/main1/V15_1_low_power/tests');O.mkdir(parents=True,exist_ok=True)
def test(name,files):
 c=subprocess.run(['iverilog','-g2012','-s','tb','-I',str(R/'source/b'),'-o',str(O/(name+'.vvp')),*map(str,files)],capture_output=True,text=True)
 (O/(name+'.compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');assert c.returncode==0,c.stderr
 start=time.monotonic();p=subprocess.run(['vvp',str(O/(name+'.vvp'))],cwd=O,capture_output=True,text=True,timeout=80)
 (O/(name+'.log')).write_text(p.stdout+p.stderr,encoding='utf-8');print(name,p.stdout,flush=True)
 assert p.returncode==0 and '_PASS' in p.stdout
 return dict(passed=True,seconds=round(time.monotonic()-start,3),log=str(O/(name+'.log')))
(O/'windows_ref.v').write_text((P/'source/b/scene_analysis_windows.v').read_text().replace('module scene_analysis_windows','module windows_ref'))
tb=r'''@@timescale 1ns/1ps
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
'''.replace('@@',chr(96))
(O/'tb_windows.v').write_text(tb)
mic=r'''@@timescale 1ns/1ps
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
'''.replace('@@',chr(96))
(O/'tb_mic.v').write_text(mic)
(O/'mic_ref.v').write_text((P/'source/b/mic_input.v').read_text().replace('module mic_input','module mic_ref'))
results={}
results['windows']=test('windows',[O/'tb_windows.v',R/'source/b/scene_analysis_windows.v',O/'windows_ref.v'])
results['microphone']=test('mic',[O/'tb_mic.v',O/'mic_ref.v',*[R/'source/b'/f for f in ('mic_input.v','mic_i2s_rx.v','mic_quantize.v','reset_sync.v','scene_cdc_mailbox.v','cdc_snapshot.v','low_power_control.v')]])
report=dict(new_execution=results,unchanged_math='Exact V15 FFT/weight/ROM source reused without rerunning',hardware_accessed=False,tf_written=False)
report['pass']=True
(R/'reports/V151_DIRECTED_TESTS.json').write_text(json.dumps(report,indent=2)+'\n')
print('V151_DIRECTED_TESTS_PASS')
