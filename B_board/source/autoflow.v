`timescale 1ns/1ps
module autoflow #(parameter integer WAIT_CYCLES=750000000, parameter integer DEMO_HZ=50000000)(
 input wire clk,rst_n,enable,eligible,manual,input wire [3:0] page,
 input wire [31:0] generation,epoch,output reg request,output reg [3:0] target,
 output wire running,output wire [29:0] elapsed,
 input wire demo_active,demo_pause,demo_restart,input wire [1:0] demo_interval);
 reg [30:0] count;reg fired,restart,demo_old;reg [31:0] old_generation,old_epoch;
 wire restart_now=!enable || !eligible || manual || generation!=old_generation || epoch!=old_epoch;
 wire [30:0] demo_limit=demo_interval==0 ? 5*DEMO_HZ:demo_interval==1 ? 10*DEMO_HZ:
  demo_interval==2 ? 15*DEMO_HZ:30*DEMO_HZ;
 assign elapsed=count[29:0];assign running=demo_active ? eligible && !demo_pause && !fired:enable && eligible && !fired;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin count<=0;fired<=0;restart<=1;request<=0;target<=0;old_generation<=0;old_epoch<=0;demo_old<=0;end
  else begin
   request<=0;old_generation<=generation;old_epoch<=epoch;restart<=restart_now;demo_old<=demo_active;
   // Restart is pipelined to keep it off the wide counter. The terminal
   // request still checks restart_now, and top checks manual/eligible again;
   // that one-cycle delay must not leak an old page request.
   if(demo_active)begin
    if(!demo_old || demo_restart || epoch!=old_epoch)begin count<=0;fired<=0;end
    else if(eligible && !demo_pause && !fired)begin
     if(count==demo_limit-1)begin count<=0;request<=1;target<=page==9 ? 0:page+1'b1;fired<=1;end
     else count<=count+1'b1;
    end
   end else if(demo_old || restart)begin count<=0;fired<=0;end
   else if(!fired)begin
    if(count==WAIT_CYCLES-1)begin count<=0;request<=!restart_now;target<=page==9 ? 0:page+1'b1;fired<=1;end
    else count<=count+1'b1;
   end
  end
 end
endmodule
