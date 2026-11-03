module link_byte_rx(input clk,input rst_n,input clear,input [7:0] command,input command_valid,
 input [7:0] f_data,input f_clk,input f_valid,output reg f_ready,
 output reg [7:0] data,output reg valid,input ready,output paused,output reg clock_active);
 reg [7:0] data_meta,data_sync;reg request_meta,request_sync,valid_meta,valid_sync;
 always @(posedge clk)if(!rst_n)begin data_meta<=0;data_sync<=0;request_meta<=0;request_sync<=0;valid_meta<=0;valid_sync<=0;end
 else begin data_meta<=f_data;data_sync<=data_meta;request_meta<=f_clk;request_sync<=request_meta;valid_meta<=f_valid;valid_sync<=valid_meta;end
 reg pause_reg,observed_request;reg [1:0] settle;assign paused=pause_reg;
 always @(posedge clk)begin
 if(!rst_n || clear)begin f_ready<=0;data<=0;valid<=0;pause_reg<=0;observed_request<=request_sync;clock_active<=0;settle<=0;end
 else begin valid<=0;
 if(request_sync!=observed_request)begin observed_request<=request_sync;clock_active<=1;end if(command_valid && command=="P")pause_reg<=~pause_reg;
 if(!valid_sync)begin f_ready<=0;settle<=0;end
 else if(!f_ready && !pause_reg && ready)begin
 if(settle!=2)settle<=settle+1'b1;
 else begin f_ready<=1;data<=data_sync;valid<=1;settle<=0;end
 end end end
endmodule

