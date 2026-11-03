`timescale 1ns/1ps
// 4096 stereo frames at AW=12. Neither BRAM port resets its data.
// After empty-to-data, qualify the synchronous lookahead before exposing valid.
// Import provenance is recorded in SOURCE_IMPORTS.json.
module scene_pcm_fifo #(parameter AW=12,SHARED_RECORD=0)(
 input wire wclk,wrst_n,push,input wire [31:0] frame_in,
 output wire full,output wire [AW:0] wcount,
 input wire rclk,rrst_n,take,output wire [31:0] frame_out,
 output wire valid,output wire [AW:0] rcount,
 input wire record_owner_w,record_owner_r,record_we,input wire [13:0] record_address,input wire [7:0] record_data,
 output wire [7:0] record_read,input wire [13:0] record_play_address,output wire [7:0] record_play_read
);
 reg [AW:0] wb,wg,rb,rg;
 // Buffer only the zero-cycle BRAM write-address branch. Keep pointer feedback,
 // Gray encoding and CDC sampling on their own registers.
 wire [AW-1:0] waddr_dly; /* fehdl keep="true" */
 genvar wa;
 generate for(wa=0;wa<AW;wa=wa+1)begin:g_waddr_delay
  AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(wb[wa]),.o(waddr_dly[wa]));
 end endgenerate
 (* ASYNC_REG="TRUE" *) reg [AW:0] rg1,rg2,wg1,wg2;
 reg preview_valid;
 // TD native EQN spells XOR as @. Explicit prefix stages prevent reassociation
 // into a serial suffix chain; they add no register or pointer latency.
 localparam PREFIX_STAGES=$clog2(AW+1);
 wire [AW:0] read_prefix[0:PREFIX_STAGES],write_prefix[0:PREFIX_STAGES];
 assign read_prefix[0]=rg2;assign write_prefix[0]=wg2;
 genvar ps,pb;
 generate for(ps=0;ps<PREFIX_STAGES;ps=ps+1)begin:g_gray_stage
  for(pb=0;pb<=AW;pb=pb+1)begin:g_bit
   if(pb+(1<<ps)<=AW)begin:g_xor
    (* keep="true" *) AL_MAP_LUT2 #(.EQN("(A@B)"),.INIT(4'b0110)) r_xor(
     .a(read_prefix[ps][pb]),.b(read_prefix[ps][pb+(1<<ps)]),.o(read_prefix[ps+1][pb]));
    (* keep="true" *) AL_MAP_LUT2 #(.EQN("(A@B)"),.INIT(4'b0110)) w_xor(
     .a(write_prefix[ps][pb]),.b(write_prefix[ps][pb+(1<<ps)]),.o(write_prefix[ps+1][pb]));
   end else begin:g_pass
    assign read_prefix[ps+1][pb]=read_prefix[ps][pb];
    assign write_prefix[ps+1][pb]=write_prefix[ps][pb];
   end
  end
 end endgenerate
 wire [AW:0] read_binary=read_prefix[PREFIX_STAGES],write_binary=write_prefix[PREFIX_STAGES];
 wire empty=rg==wg2;
 assign full=wg=={~rg2[AW:AW-1],rg2[AW-2:0]};
 assign valid=preview_valid && !empty;
 assign wcount=wb-read_binary;assign rcount=write_binary-rb;
 wire [AW:0] wn=wb+(push && !full);
 wire [AW:0] rn=rb+(take && valid);
 always @(posedge wclk or negedge wrst_n)begin
  if(!wrst_n)begin wb<=0;wg<=0;rg1<=0;rg2<=0;end
  else begin
   rg1<=rg;rg2<=rg1;wb<=wn;wg<=(wn>>1)^wn;
  end
 end
 always @(posedge rclk or negedge rrst_n)begin
  if(!rrst_n)begin rb<=0;rg<=0;wg1<=0;wg2<=0;preview_valid<=0;end
  else begin
   wg1<=wg;wg2<=wg1;rb<=rn;rg<=(rn>>1)^rn;
   preview_valid<=rn!=write_binary;
  end
 end
 // Four byte lanes store each 32-bit stereo frame atomically. Port A writes
 // at wclk; port B supplies synchronous lookahead without a data reset or extra
 // output register. Gray/preview qualification hides empty-state collisions.
 wire borrow_w=SHARED_RECORD && record_owner_w,borrow_r=SHARED_RECORD && record_owner_r;
 wire [31:0] record_sys_words;
 generate if(SHARED_RECORD)begin:g_record_read
  reg [1:0] sys_lane,audio_lane;
  always @(posedge wclk)sys_lane<=record_address[13:12];
  always @(posedge rclk)audio_lane<=record_play_address[13:12];
  assign record_read=record_sys_words[sys_lane*8+:8];
  assign record_play_read=frame_out[audio_lane*8+:8];
 end else begin:g_no_record_read
  assign record_read=8'd0;assign record_play_read=8'd0;
 end endgenerate
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:g_pcm_lane
  EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
   .DATA_DEPTH_A(1<<AW),.DATA_DEPTH_B(1<<AW),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
   .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K")) memory(
   .doa(record_sys_words[lane*8+:8]),.dob(frame_out[lane*8+:8]),.dia(borrow_w ? record_data:frame_in[lane*8+:8]),.dib(8'd0),
   .cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),.clka(wclk),.clkb(rclk),
   .wea(borrow_w ? (record_we && record_address[13:12]==lane):(wrst_n && push && !full)),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
   .addra(borrow_w ? record_address[AW-1:0]:waddr_dly),.addrb(borrow_r ? record_play_address[AW-1:0]:rn[AW-1:0]));
 end endgenerate
endmodule
