`timescale 1ns/1ps

module auto_status_pipe #(parameter integer SECOND_CYCLES=50000000)(
 input wire clk,rst_n,enable,running,input wire [29:0] elapsed,
 input wire fault,menu,voice,mic,pause,held,loading,ready,
 output wire [3:0] seconds,reason,input wire volume_mode);
// UI gets a coherent one-cycle snapshot; autoflow still owns the real timer.
 reg volume_q;
 always @(posedge clk or negedge rst_n)if(!rst_n)volume_q<=0;else volume_q<=volume_mode;
 wire [3:0] base_reason;
 assign reason=volume_q && observation[39] && !observation[7] && !observation[6] && !observation[5] && !observation[4] ? 4'd10:base_reason;
 reg [39:0] observation;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)observation<=0;
  else observation<={enable,running,elapsed,fault,menu,voice,mic,pause,held,loading,ready};
 auto_status_view #(.SECOND_CYCLES(SECOND_CYCLES)) view(clk,rst_n,observation[39],observation[38],observation[37:8],
 observation[7],observation[6],observation[5],observation[4],observation[3],observation[2],observation[1],observation[0],seconds,base_reason);
endmodule
