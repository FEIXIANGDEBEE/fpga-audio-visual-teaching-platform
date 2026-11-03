`timescale 1ns/1ps
// Two resumable contexts share one byte packer. Bind after the destination
// FIFO is cleared. Assemble a full L/R frame before publication, then hold
// it through backpressure. L occupies bits [15:0], R [31:16]; mono duplicates L.
module scene_wav_packer #(parameter HIGH_FRAMES=3584,MAX_FILE_BYTES=67108864)(
 input wire clk,rst_n,
 input wire bind_valid,bind_bank,input wire [1:0] bind_scene,input wire [96:0] bind_descriptor,
 output wire bind_ready,output reg bind_done,
 input wire [1:0] enable,input wire [12:0] count0,count1,
 output wire [1:0] demand,available,output wire [31:0] offset0,offset1,
 output wire [3:0] file0,file1,
 input wire accepted,accepted_bank,
 input wire response_valid,response_error,response_bank,input wire [7:0] response_data,
 output reg frame_valid,frame_bank,output reg [31:0] frame_data,input wire frame_ready,
 output reg [1:0] bound,fault,output reg [7:0] error_code,
 output wire [31:0] frames0,frames1,loops0,loops1
);
 reg [1:0] scene[0:1];reg stereo[0:1];
 localparam OFFSET_W=$clog2(MAX_FILE_BYTES+1);
 reg [OFFSET_W-1:0] base[0:1],length[0:1],cursor[0:1],remaining[0:1];
 reg [23:0] partial[0:1];reg [1:0] phase[0:1];
 reg [31:0] frames[0:1],loops[0:1];
 reg pending,pending_bank,frame_last;
 // A short loop may straddle sectors and exhaust SPI bandwidth if repeatedly
 // read. Cache the first verified loop, up to 128 frames per context, in a shared
 // 256x32 RAM; subsequent loops refill the FIFO from that held copy.
 (* force_ram, ram_style="bram" *) reg [31:0] short_ram[0:255];
 reg [7:0] short_raddr;reg [31:0] short_q;
 reg [1:0] short_mode,short_valid,cache_state;
 reg [6:0] short_index[0:1],short_last[0:1];
 reg cache_bank,cache_turn,frame_cached;
 wire [1:0] need;
 wire [1:0] cache_need=need & short_valid;
 wire selected_cache=cache_need[cache_turn] ? cache_turn : ~cache_turn;
 wire cache_start=(|cache_need) && !pending && !frame_valid && cache_state==0 && !bind_valid;
 always @(posedge clk)begin
  short_q<=short_ram[short_raddr];
  if(frame_valid && frame_ready && short_mode[frame_bank] && !short_valid[frame_bank] && !frame_cached)
   short_ram[{frame_bank,short_index[frame_bank]}]<=frame_data;
 end
 wire final_byte=stereo[response_bank] ? phase[response_bank]==3 : phase[response_bank]==1;
 assign bind_ready=!pending && !frame_valid && cache_state==0;
 assign need[0]=bound[0] && enable[0] && !fault[0] && count0<HIGH_FRAMES;
 assign need[1]=bound[1] && enable[1] && !fault[1] && count1<HIGH_FRAMES;
 assign demand=need & ~short_valid;
 assign available=demand & {2{!pending && !frame_valid && !bind_valid && cache_state==0 && !cache_start}};
 assign offset0=cursor[0];assign offset1=cursor[1];
 assign file0={2'b0,scene[0]}+4'd10;assign file1={2'b0,scene[1]}+4'd10;
 assign frames0=frames[0];assign frames1=frames[1];assign loops0=loops[0];assign loops1=loops[1];
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   bound<=0;fault<=0;error_code<=0;pending<=0;pending_bank<=0;bind_done<=0;
   frame_valid<=0;frame_bank<=0;frame_data<=0;frame_last<=0;
   short_mode<=0;short_valid<=0;short_raddr<=0;cache_state<=0;cache_bank<=0;cache_turn<=0;frame_cached<=0;
   for(i=0;i<2;i=i+1)begin
    scene[i]<=0;stereo[i]<=0;base[i]<=0;length[i]<=0;cursor[i]<=0;remaining[i]<=0;
    partial[i]<=0;phase[i]<=0;frames[i]<=0;loops[i]<=0;
    short_index[i]<=0;short_last[i]<=0;
   end
  end else begin
   bind_done<=0;
   if(bind_valid && bind_ready)begin
    // Reject invalid descriptors even if the caller binds the wrong context.
    if(bind_descriptor[63:32]==0 || bind_descriptor[95:64]==0 ||
       (bind_descriptor[96] ? bind_descriptor[33:32]!=0 : bind_descriptor[32]!=0) ||
       bind_descriptor[95:64]!=(bind_descriptor[96] ? bind_descriptor[63:32]>>2 : bind_descriptor[63:32]>>1) ||
       {1'b0,bind_descriptor[31:0]}+{1'b0,bind_descriptor[63:32]}>MAX_FILE_BYTES)begin
     fault[bind_bank]<=1;bound[bind_bank]<=0;error_code<=8'h42;
    end else begin
     bound[bind_bank]<=1;fault[bind_bank]<=0;scene[bind_bank]<=bind_scene;stereo[bind_bank]<=bind_descriptor[96];
     base[bind_bank]<=bind_descriptor[31:0];length[bind_bank]<=bind_descriptor[63:32];
     cursor[bind_bank]<=bind_descriptor[31:0];remaining[bind_bank]<=bind_descriptor[63:32];
     phase[bind_bank]<=0;partial[bind_bank]<=0;frames[bind_bank]<=0;loops[bind_bank]<=0;
     short_mode[bind_bank]<=(bind_descriptor[95:64]<=128);
     short_valid[bind_bank]<=0;short_index[bind_bank]<=0;short_last[bind_bank]<=bind_descriptor[70:64]-1'b1;
    end
    bind_done<=1;
   end
   if(accepted)begin pending<=1;pending_bank<=accepted_bank;end
   if(response_valid || response_error)begin
    pending<=0;
    if(!pending || response_bank!=pending_bank || response_error || frame_valid)begin
     fault[pending_bank]<=1;error_code<=8'h40;
    end else begin
     partial[response_bank]<={response_data,partial[response_bank][23:8]};
     cursor[response_bank]<=cursor[response_bank]+1'b1;remaining[response_bank]<=remaining[response_bank]-1'b1;
     if(final_byte)begin
      frame_cached<=0;
      frame_data<=stereo[response_bank] ? {response_data,partial[response_bank]} :
       {response_data,partial[response_bank][23:16],response_data,partial[response_bank][23:16]};
      frame_valid<=1;frame_bank<=response_bank;frame_last<=remaining[response_bank]==1;
      phase[response_bank]<=0;
     end else phase[response_bank]<=phase[response_bank]+1'b1;
     if(remaining[response_bank]==1)begin
      if(!final_byte)begin fault[response_bank]<=1;error_code<=8'h42;frame_valid<=0;end
      else begin cursor[response_bank]<=base[response_bank];remaining[response_bank]<=length[response_bank];end
     end
    end
   end
   if(frame_valid && frame_ready)begin
    frame_valid<=0;frames[frame_bank]<=frames[frame_bank]+1'b1;
    if(frame_last)loops[frame_bank]<=loops[frame_bank]+1'b1;
    if(short_mode[frame_bank])begin
     if(short_index[frame_bank]==short_last[frame_bank])begin
      short_index[frame_bank]<=0;
      if(!frame_cached)short_valid[frame_bank]<=1;
     end else short_index[frame_bank]<=short_index[frame_bank]+1'b1;
    end
   end
   if(cache_start)begin
    cache_bank<=selected_cache;short_raddr<={selected_cache,short_index[selected_cache]};cache_state<=1;
   end
   if(cache_state==1)cache_state<=2;
   if(cache_state==2)begin
    frame_valid<=1;frame_bank<=cache_bank;frame_data<=short_q;frame_cached<=1;
    frame_last<=short_index[cache_bank]==short_last[cache_bank];cache_state<=0;cache_turn<=~cache_bank;
   end
  end
 end
endmodule
