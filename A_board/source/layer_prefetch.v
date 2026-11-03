`timescale 1ns/1ps
// One sample per plane, with four published rows per plane and independent retirement.
module layer_prefetch(
 input wire mclk,mrst_n,pclk,prst_n,input wire frame_start,input wire enabled,
 input wire [8:0] retire_bg,retire_fg,
 input wire [8:0] bg_y,fg_y,input wire [8:0] bg_x,input wire [7:0] fg_x,
 output wire request,output wire [20:0] address,input wire request_ready,
 input wire data_valid,input wire [31:0] data,input wire burst_done,burst_error,
 output wire rows_ready,output reg fault,output wire [23:0] bg_pixel,output wire [31:0] fg_pixel,output wire mode
);
 reg frame_toggle;reg [8:0] bg_ret_gray;reg [8:0] fg_ret_gray;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin frame_toggle<=0;bg_ret_gray<=0;fg_ret_gray<=0;end
  else begin if(frame_start)frame_toggle<=!frame_toggle;bg_ret_gray<=retire_bg^(retire_bg>>1);fg_ret_gray<=retire_fg^(retire_fg>>1);end
 end
 (* ASYNC_REG="TRUE" *) reg epoch_m1,epoch_m2;(* ASYNC_REG="TRUE" *) reg [8:0] rb1,rb2;(* ASYNC_REG="TRUE" *) reg [8:0] rf1,rf2;
 wire [8:0] retired_b;wire [8:0] retired_f;genvar k;
 generate for(k=0;k<9;k=k+1)begin:gb assign retired_b[k]=^(rb2>>k);end
 for(k=0;k<9;k=k+1)begin:gf assign retired_f[k]=^(rf2>>k);end endgenerate
 reg epoch_seen,active,owner,outstanding,prefer_fg;reg [17:0] bg_offset;reg [16:0] fg_offset;
 reg [8:0] bg_col,bg_row;reg [7:0] fg_col;reg [8:0] fg_row;reg [8:0] received;
 reg [18:0] bg_end,fg_end;reg [2:0] epoch_settle;
 always @(posedge mclk or negedge mrst_n)begin
  if(!mrst_n)begin bg_end<=19'd1768;fg_end<=19'd852;end
  else begin bg_end<=({10'd0,retired_b}+19'd4)*19'd442;fg_end<=({10'd0,retired_f}+19'd4)*19'd213;end
 end
 // Offsets start at zero and advance by 256, so their low eight bits stay zero.
 // 256*(block+1)<=end reduces to block<floor(end/256) without 19-bit overflow.
 wire bg_room=bg_offset[17:8]<10'd553 && ((bg_offset[17:8]<bg_end[18:8]) || retired_b>=316);
 wire fg_room=fg_offset[16:8]<9'd267 && ((fg_offset[16:8]<fg_end[18:8]) || retired_f>=316);
 wire choose_fg=fg_room && (prefer_fg || !bg_room);
 assign mode=active || outstanding;
 assign request=active && epoch_settle==0 && !outstanding && !fault && epoch_m2==epoch_seen && (bg_room || fg_room);
 assign address=choose_fg ? 21'd141568+fg_offset:bg_offset;
 wire wb=data_valid && outstanding && !owner && received<256 && bg_offset+received<141440;
 wire wf=data_valid && outstanding && owner && received<256 && fg_offset+received<68160;
 p2_row_ram #(.W(24),.AW(11),.DEPTH(2048),.IMPL("9K")) bg_ram(mclk,wb,{bg_row[1:0],bg_col},data[23:0],pclk,{bg_y[1:0],bg_x},bg_pixel);
 p2_row_ram #(.W(32),.AW(10),.DEPTH(1024),.IMPL("32K")) fg_ram(mclk,wf,{fg_row[1:0],fg_col},data,pclk,{fg_y[1:0],fg_x},fg_pixel);
 reg [8:0] bg_tag[0:3];reg [8:0] fg_tag[0:3];reg [3:0] bg_epoch,fg_epoch,pub_bg,pub_fg;
 (* ASYNC_REG="TRUE" *) reg [3:0] pb1,pb2,pf1,pf2;
 reg [3:0] seen_bg,seen_fg,pv_bg,pv_fg,pe_bg,pe_fg;reg [8:0] pt_bg[0:3];reg [8:0] pt_fg[0:3];integer i;
 always @(posedge pclk or negedge prst_n)begin
  if(!prst_n)begin pb1<=0;pb2<=0;pf1<=0;pf2<=0;seen_bg<=0;seen_fg<=0;pv_bg<=0;pv_fg<=0;pe_bg<=0;pe_fg<=0;
   for(i=0;i<4;i=i+1)begin pt_bg[i]<=0;pt_fg[i]<=0;end
  end else begin
   pb1<=pub_bg;pb2<=pb1;pf1<=pub_fg;pf2<=pf1;
   for(i=0;i<4;i=i+1)begin
    if(pb2[i]!=seen_bg[i])begin seen_bg[i]<=pb2[i];pt_bg[i]<=bg_tag[i];pe_bg[i]<=bg_epoch[i];pv_bg[i]<=1;end
    if(pf2[i]!=seen_fg[i])begin seen_fg[i]<=pf2[i];pt_fg[i]<=fg_tag[i];pe_fg[i]<=fg_epoch[i];pv_fg[i]<=1;end
   end
  end
 end
 assign rows_ready=pv_bg[bg_y[1:0]] && pv_fg[fg_y[1:0]] && pt_bg[bg_y[1:0]]==bg_y && pt_fg[fg_y[1:0]]==fg_y && pe_bg[bg_y[1:0]]==frame_toggle && pe_fg[fg_y[1:0]]==frame_toggle;
 always @(posedge mclk or negedge mrst_n)begin
  if(!mrst_n)begin epoch_m1<=0;epoch_m2<=0;rb1<=0;rb2<=0;rf1<=0;rf2<=0;epoch_seen<=0;active<=0;owner<=0;outstanding<=0;prefer_fg<=0;epoch_settle<=0;
   bg_offset<=0;fg_offset<=0;bg_col<=0;fg_col<=0;bg_row<=0;fg_row<=0;received<=0;bg_epoch<=0;fg_epoch<=0;pub_bg<=0;pub_fg<=0;fault<=0;
   for(i=0;i<4;i=i+1)begin bg_tag[i]<=0;fg_tag[i]<=0;end
  end else begin
   epoch_m1<=frame_toggle;epoch_m2<=epoch_m1;rb1<=bg_ret_gray;rb2<=rb1;rf1<=fg_ret_gray;rf2<=rf1;
   if(epoch_settle!=0)epoch_settle<=epoch_settle-1'b1;
   if(epoch_m2!=epoch_seen && !outstanding)begin epoch_seen<=epoch_m2;active<=enabled;epoch_settle<=3'd6;bg_offset<=0;fg_offset<=0;bg_col<=0;fg_col<=0;bg_row<=0;fg_row<=0;fault<=0;end
   else if(request && request_ready)begin outstanding<=1;owner<=choose_fg;prefer_fg<=!choose_fg;received<=0;end
   if(data_valid && outstanding)begin
    received<=received+1'b1;if(received>=256)fault<=1;
    if(wf)begin if(fg_col==212)begin fg_col<=0;fg_row<=fg_row+1'b1;fg_tag[fg_row[1:0]]<=fg_row;fg_epoch[fg_row[1:0]]<=epoch_seen;pub_fg[fg_row[1:0]]<=!pub_fg[fg_row[1:0]];end else fg_col<=fg_col+1'b1;end
    if(wb)begin if(bg_col==441)begin bg_col<=0;bg_row<=bg_row+1'b1;bg_tag[bg_row[1:0]]<=bg_row;bg_epoch[bg_row[1:0]]<=epoch_seen;pub_bg[bg_row[1:0]]<=!pub_bg[bg_row[1:0]];end else bg_col<=bg_col+1'b1;end
   end
   if(burst_done && outstanding)begin outstanding<=0;if(burst_error || received!=256)fault<=1;else if(owner)fg_offset<=fg_offset+17'd256;else bg_offset<=bg_offset+18'd256;end
  end
 end
endmodule
module p2_row_ram #(parameter W=24,AW=11,DEPTH=2048,parameter IMPL="9K")(input wire wc,we,input wire [AW-1:0] wa,input wire [W-1:0] wd,input wire rc,input wire [AW-1:0] ra,output wire [W-1:0] rd);
`ifdef V120_SIM
 reg [W-1:0] mem[0:DEPTH-1];reg [W-1:0] q;assign rd=q;always @(posedge wc)if(we)mem[wa]<=wd;always @(posedge rc)q<=mem[ra];
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(W),.DATA_WIDTH_B(W),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),.DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT(IMPL)) memory(.doa(),.dob(rd),.dia(wd),.dib({W{1'b0}}),.cea(we),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),.clka(wc),.clkb(rc),.wea(we),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(wa),.addrb(ra));
`endif
endmodule
