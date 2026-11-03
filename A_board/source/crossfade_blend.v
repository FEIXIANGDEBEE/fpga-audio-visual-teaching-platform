`timescale 1ns/1ps
// Buffer one aligned old-image block. Pair synchronous reads with new-image
// beats and use three signed difference products for RGB blending.
module crossfade_blend(
 input wire clk,rst_n,flush,old_valid,new_valid,
 input wire [7:0] beat,
 input wire [23:0] data,
 input wire [8:0] alpha,
 output reg valid,
 output reg [23:0] rgb
);
 reg [23:0] scratch[0:255];
 wire [7:0] ram_addr; /* fehdl keep="true" */
 wire [23:0] ram_data; /* fehdl keep="true" */
 wire ram_we; /* fehdl keep="true" */
 genvar b;
 generate for(b=0;b<8;b=b+1)begin:g_cf_addr_delay
  AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(beat[b]),.o(ram_addr[b]));
 end
 for(b=0;b<24;b=b+1)begin:g_cf_data_delay
  AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(data[b]),.o(ram_data[b]));
 end endgenerate
 generate for(b=0;b<1;b=b+1)begin:g_cf_we_delay
  AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(old_valid),.o(ram_we));
 end endgenerate
 reg [23:0] old_q,new_q,base2,base3;
 reg v1,v2,v3;
 reg signed [8:0] dr,dg,db;
 reg signed [18:0] pr,pg,pb;
 wire signed [18:0] rr=$signed({3'b000,base3[23:16],8'd0})+pr+19'sd128;
 wire signed [18:0] rg=$signed({3'b000,base3[15:8],8'd0})+pg+19'sd128;
 wire signed [18:0] rb=$signed({3'b000,base3[7:0],8'd0})+pb+19'sd128;
 // Validity hides stale pixels, so neither RAM data nor its read register needs reset.
 always @(posedge clk)begin
  if(ram_we)scratch[ram_addr]<=ram_data;
  old_q<=scratch[ram_addr];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   new_q<=0;base2<=0;base3<=0;dr<=0;dg<=0;db<=0;
   pr<=0;pg<=0;pb<=0;v1<=0;v2<=0;v3<=0;valid<=0;rgb<=0;
  end else begin
   new_q<=data;
   v1<=new_valid && !flush;v2<=v1 && !flush;v3<=v2 && !flush;valid<=v3 && !flush;
   base2<=old_q;
   dr<=$signed({1'b0,new_q[23:16]})-$signed({1'b0,old_q[23:16]});
   dg<=$signed({1'b0,new_q[15:8]})-$signed({1'b0,old_q[15:8]});
   db<=$signed({1'b0,new_q[7:0]})-$signed({1'b0,old_q[7:0]});
   pr<=dr*$signed({1'b0,alpha});pg<=dg*$signed({1'b0,alpha});pb<=db*$signed({1'b0,alpha});
   base3<=base2;
   rgb<={rr[15:8],rg[15:8],rb[15:8]};
  end
 end
endmodule
