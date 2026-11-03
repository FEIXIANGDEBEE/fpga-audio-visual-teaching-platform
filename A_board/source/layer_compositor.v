`timescale 1ns/1ps
// Compose full-height foreground with dwell/lag motion and Q2 interpolation.
// Keep pixel metadata aligned through the six-cycle pipeline.
module layer_compositor(
 input wire pclk,prst_n,mclk,mrst_n,input wire enable,stop_motion,
 input wire hs,vs,de,input wire [9:0] x,y,input wire [23:0] rgb,input wire active,input wire [31:0] id,
 output wire ohs,ovs,ode,output wire [9:0] ox,oy,output wire [23:0] orgb,output wire oactive,output wire [31:0] oid,
 output wire request,output wire [20:0] address,input wire request_ready,input wire data_valid,input wire [31:0] data,input wire burst_done,burst_error,
 output reg safe,output reg deadline_fault,output wire layer_mode,
 input wire [1:0] motion_level,output wire running,output reg [7:0] missed_lines
);
 wire boundary=x==0 && y==480;reg frame_enable;reg [8:0] phase;reg signed [6:0] fg_shift;reg signed [5:0] bg_shift;
 reg [1:0] active_level;
 // The next consumer is the following 800x525 frame boundary, leaving time
 // for a synchronous motion-table read. Entry 0 and the first reset-release
 // fallback are both zero.
 reg motion_ready;wire [17:0] motion_word;
 always @(posedge pclk or negedge prst_n)if(!prst_n)motion_ready<=0;else motion_ready<=1;
`ifdef V120_SIM
 reg [17:0] motion[0:511];reg [17:0] motion_q;
 initial $readmemh("motion_native.dath",motion);
 always @(posedge pclk)motion_q<=motion[phase];
 assign motion_word=motion_q;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(18),.DATA_WIDTH_B(18),.ADDR_WIDTH_A(9),.ADDR_WIDTH_B(9),
  .DATA_DEPTH_A(512),.DATA_DEPTH_B(512),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE("motion_native.dath")) motion_rom(
  .doa(motion_word),.dob(),.dia(18'd0),.dib(18'd0),.cea(1'b1),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
  .clka(pclk),.clkb(pclk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(phase),.addrb(9'd0));
`endif
 wire signed [6:0] table_fg=motion_word[6:0];wire signed [5:0] table_bg=motion_word[12:7];
 assign running=frame_enable && !deadline_fault && (fg_shift!=0 || bg_shift!=0);
 wire [9:0] lx=x>=24 && x<450 ? x-24:0;wire [9:0] ly=y>=100 && y<420 ? y-100:0;
 wire signed [6:0] fi=fg_shift>>>2;wire signed [5:0] bi=bg_shift>>>2;
 wire signed [11:0] fx=$signed({2'b00,lx})-$signed({{5{fi[6]}},fi});
 wire signed [11:0] bx=$signed({2'b00,lx})+12'sd8-$signed({{6{bi[5]}},bi});
 wire f_valid=fx>=0 && fx<426;wire [7:0] f_x=f_valid ? fx[8:1]:0;wire [8:0] b_x=(bx>=0 && bx<442) ? bx[8:0]:0;
 reg [8:0] retired_bg,retired_fg;wire [23:0] b;wire [31:0] f;wire ready,cache_fault;
 layer_prefetch prefetch(mclk,mrst_n,pclk,prst_n,boundary,frame_enable,retired_bg,retired_fg,ly[8:0],ly[8:0],b_x,f_x,
 request,address,request_ready,data_valid,data,burst_done,burst_error,ready,cache_fault,b,f,layer_mode);
 reg fault_m1,fault_p,line_ok,valid_q;reg [1:0] bf_q,ff_q;reg [23:0] bundle[0:5],base[0:5];reg [5:0] use_fx;
 reg [31:0] pending_id,published_id;reg [2:0] id_delay;reg [15:0] pr,pg,pb;reg [23:0] fg,results[0:2];integer k;
 reg [23:0] b_prev,b_mix;reg [31:0] f_prev,f_mix;
 function [7:0] lerp4;input [7:0] curr,prev;input [1:0] frac;reg [8:0] pair,extra;reg [9:0] sum;begin
  pair={1'b0,curr}+{1'b0,prev};
  case(frac)
   1:extra={curr,1'b0};
   3:extra={prev,1'b0};
   default:extra=pair;
  endcase
  sum={1'b0,pair}+{1'b0,extra}+10'd2;
  lerp4=frac==0 ? curr:sum[9:2];
 end endfunction
 function [7:0] composite;input [7:0] p;input [15:0] product;reg [16:0] t,z;reg [8:0] q;begin t={1'b0,product}+17'd128;z=t+(t>>8);q=p+(z>>8);composite=q>255 ? 8'd255:q[7:0];end endfunction
 assign {oactive,ohs,ovs,ode,ox,oy}=bundle[5];assign oid=published_id;assign orgb=use_fx[5] ? results[2]:base[5];
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin frame_enable<=0;phase<=0;fg_shift<=0;bg_shift<=0;active_level<=2;missed_lines<=0;safe<=1;retired_bg<=0;retired_fg<=0;pending_id<=0;published_id<=0;id_delay<=0;
   fault_m1<=0;fault_p<=0;line_ok<=0;deadline_fault<=0;valid_q<=0;bf_q<=0;ff_q<=0;use_fx<=0;pr<=0;pg<=0;pb<=0;fg<=0;b_prev<=0;f_prev<=0;b_mix<=0;f_mix<=0;
   for(k=0;k<6;k=k+1)begin bundle[k]<=0;base[k]<=0;end for(k=0;k<3;k=k+1)results[k]<=0;
  end else begin
   fault_m1<=cache_fault;fault_p<=fault_m1;
   if(id!=pending_id)begin pending_id<=id;id_delay<=5;end else if(id_delay!=0)begin id_delay<=id_delay-1'b1;if(id_delay==1)published_id<=pending_id;end
   if(boundary)begin frame_enable<=enable && !deadline_fault && (motion_level!=0 || fg_shift!=0 || bg_shift!=0);retired_bg<=0;retired_fg<=0;
    if(!enable || deadline_fault)begin phase<=0;fg_shift<=0;bg_shift<=0;safe<=1;active_level<=motion_level;end
    else if(stop_motion || motion_level!=active_level || motion_level==0)begin
     if(fg_shift>2)fg_shift<=fg_shift-7'sd2;else if(fg_shift< -2)fg_shift<=fg_shift+7'sd2;else fg_shift<=0;
     if(bg_shift>1)bg_shift<=bg_shift-6'sd1;else if(bg_shift< -1)bg_shift<=bg_shift+6'sd1;else bg_shift<=0;
     safe<=fg_shift==0 && bg_shift==0;
     if(fg_shift==0 && bg_shift==0)begin active_level<=motion_level;phase<=0;end
    end else begin safe<=0;fg_shift<=!motion_ready ? 7'sd0:active_level==1 ? (table_fg>>>1):table_fg;bg_shift<=!motion_ready ? 6'sd0:active_level==1 ? (table_bg>>>1):table_bg;phase<=phase+1'b1;end
   end
   if(x==640 && y>=100 && y<419)begin retired_bg<=y-99;retired_fg<=y-99;end
   if(x==8)line_ok<=ready && !fault_p;
   if(x==24 && y>=101 && y<419 && frame_enable && !line_ok)begin deadline_fault<=1;if(missed_lines!=255)missed_lines<=missed_lines+1'b1;end
   bundle[0]<={active,hs,vs,de,x,y};base[0]<=rgb;use_fx[0]<=de && frame_enable && !deadline_fault && x>=25 && x<449 && y>=101 && y<419 && (fg_shift!=0 || bg_shift!=0) && line_ok;
   for(k=1;k<6;k=k+1)begin bundle[k]<=bundle[k-1];base[k]<=base[k-1];use_fx[k]<=use_fx[k-1];end
   valid_q<=f_valid;bf_q<=bg_shift[1:0];ff_q<=fg_shift[1:0];
   b_prev<=b;f_prev<=valid_q ? f:32'd0;
   for(k=0;k<3;k=k+1)b_mix[k*8+:8]<=lerp4(b[k*8+:8],b_prev[k*8+:8],bf_q);
   for(k=0;k<4;k=k+1)f_mix[k*8+:8]<=lerp4(valid_q ? f[k*8+:8]:8'd0,f_prev[k*8+:8],ff_q);
   fg<=f_mix[23:0];pr<=b_mix[23:16]*(8'd255-f_mix[31:24]);pg<=b_mix[15:8]*(8'd255-f_mix[31:24]);pb<=b_mix[7:0]*(8'd255-f_mix[31:24]);
   results[0]<={composite(fg[23:16],pr),composite(fg[15:8],pg),composite(fg[7:0],pb)};
   for(k=1;k<3;k=k+1)results[k]<=results[k-1];
  end
 end
endmodule
