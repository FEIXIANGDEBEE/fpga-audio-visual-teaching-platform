`timescale 1ns/1ps
// Two small mono windows observe actual post-mute output PCM. No ready goes
// back to audio. Channel changes are tagged at complete 512-frame boundaries.
// A busy analyzer drops an entire window and counts it; it never joins gaps.
module windows_ref #(parameter V18_IDENTITY=0,V22_SOURCE=0)(
 input wire clk,rst_n,frame_valid,input wire [31:0] frame,input wire select_right,
 output reg fft_start,output wire [31:0] fft_window,
 output wire fft_sample_valid,output wire signed [15:0] fft_sample,
 input wire fft_sample_ready,fft_busy,fft_done,
 output wire result_valid,input wire result_ready,
 output wire [31:0] result_generation,result_base,result_crc,output wire result_right,
 output reg [31:0] actual_frames,completed_windows,dropped_windows,errors,generation,
 input wire [6:0] frame_tag,output wire [6:0] result_tag,output wire result_mixed,
 input wire abort_capture,input wire [2:0] frame_context,input wire [31:0] frame_generation,
 output wire [2:0] result_context
);
 `include "crc32_defs.vh"
 localparam EMPTY=0,FILL=1,FULL=2,PROCESS=3;
 reg [1:0] status0,status1;reg [8:0] capture_pos,read_pos,read_addr;
 reg capture_bank,capture_drop,active_right,process_bank;
 reg [2:0] phase,crc_phase;reg [15:0] crc_sample,read0,read1,sample;
 reg [31:0] crc,read_crc,base0,base1,gen0,gen1,crc0,crc1;
 reg right0,right1;reg last_byte,crc_bank;
 reg [2:0] context0,context1;reg [31:0] next_base;
 assign result_context=process_bank ? context1 : context0;
 reg [6:0] tag0,tag1,active_tag;reg mixed0,mixed1,active_mixed;
 wire [6:0] tag=V18_IDENTITY ? frame_tag : 7'b0010000;
 assign result_tag=process_bank ? tag1 : tag0;
 assign result_mixed=process_bank ? mixed1 : mixed0;
 (* force_ram,ram_style="bram" *) reg [15:0] ram0[0:511],ram1[0:511];
 // High/low byte phases are exclusive within each independent CRC context.
 wire [7:0] capture_byte=crc_phase==1 ? crc_sample[15:8]:crc_sample[7:0];
 wire [7:0] process_byte=phase==3 ? sample[15:8]:sample[7:0];
 wire [31:0] capture_crc_next=crc32_byte(crc,capture_byte);
 wire [31:0] process_crc_next=crc32_byte(read_crc,process_byte);
 wire free0=status0==EMPTY,free1=status1==EMPTY;
 wire selected_bank=capture_pos==0 ? !free0 : capture_bank;
 wire dropping=capture_pos==0 ? !(free0 || free1) : capture_drop;
 wire right=capture_pos==0 ? select_right : active_right;
 wire [15:0] selected_sample=right ? frame[31:16] : frame[15:0];
 wire [31:0] next_generation=V22_SOURCE ? frame_generation : generation+(select_right!=active_right);
 assign fft_window=(process_bank ? base1 : base0)>>9;
 assign fft_sample_valid=phase==3;assign fft_sample=$signed(sample);
 assign result_valid=phase==6;
 assign result_generation=process_bank ? gen1 : gen0;
 assign result_right=process_bank ? right1 : right0;
 assign result_base=process_bank ? base1 : base0;assign result_crc=process_bank ? crc1 : crc0;
 always @(posedge clk)begin
  if(frame_valid && !dropping)begin
   if(selected_bank)ram1[capture_pos]<=selected_sample;else ram0[capture_pos]<=selected_sample;
  end
  read0<=ram0[read_addr];read1<=ram1[read_addr];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   status0<=EMPTY;status1<=EMPTY;capture_pos<=0;read_pos<=0;read_addr<=0;capture_bank<=0;capture_drop<=0;
   active_right<=0;process_bank<=0;phase<=0;crc_phase<=0;crc_sample<=0;sample<=0;crc<=32'hffffffff;read_crc<=32'hffffffff;
   base0<=0;base1<=0;gen0<=0;gen1<=0;crc0<=0;crc1<=0;right0<=0;right1<=0;
   last_byte<=0;crc_bank<=0;fft_start<=0;actual_frames<=0;completed_windows<=0;dropped_windows<=0;errors<=0;generation<=0;
   context0<=0;context1<=0;next_base<=0;tag0<=0;tag1<=0;active_tag<=0;mixed0<=0;mixed1<=0;active_mixed<=0;
  end else begin
   if(fft_start && fft_busy)fft_start<=0;
   if(V22_SOURCE && abort_capture)begin
    if(capture_pos!=0)begin
     if(!capture_drop)begin if(capture_bank)status1<=EMPTY;else status0<=EMPTY;end
     dropped_windows<=dropped_windows+1'b1;
    end
    capture_pos<=0;capture_drop<=0;crc_phase<=0;
   end
   if(frame_valid && !(V22_SOURCE && abort_capture))begin
    actual_frames<=actual_frames+1'b1;capture_pos<=capture_pos+1'b1;
    if(capture_pos==0)begin
     if(V22_SOURCE)next_base<=next_base+512;
     capture_bank<=selected_bank;capture_drop<=dropping;active_right<=select_right;generation<=next_generation;
     active_tag<=tag;active_mixed<=0;
     if(dropping)dropped_windows<=dropped_windows+1'b1;
     else if(selected_bank)begin status1<=FILL;base1<=V22_SOURCE ? next_base : actual_frames;context1<=frame_context;gen1<=next_generation;right1<=select_right;tag1<=tag;mixed1<=0;end
     else begin status0<=FILL;base0<=V22_SOURCE ? next_base : actual_frames;context0<=frame_context;gen0<=next_generation;right0<=select_right;tag0<=tag;mixed0<=0;end
    end
    else if(tag!=active_tag || select_right!=active_right)begin
     active_mixed<=1;
     if(selected_bank)mixed1<=1;else mixed0<=1;
    end
    if(!dropping)begin
     if(crc_phase!=0)errors<=errors+1'b1;
     crc_sample<=selected_sample;crc_phase<=1;last_byte<=capture_pos==511;crc_bank<=selected_bank;
     if(capture_pos==0)crc<=32'hffffffff;
    end
   end
   if(crc_phase==1)begin crc<=capture_crc_next;crc_phase<=2;end
   else if(crc_phase==2)begin
    crc<=capture_crc_next;crc_phase<=0;
    if(last_byte)begin
     if(crc_bank)begin crc1<=~capture_crc_next;status1<=FULL;end
     else begin crc0<=~capture_crc_next;status0<=FULL;end
    end
   end
   case(phase)
    0:if(!fft_busy && (status0==FULL || status1==FULL))begin
     process_bank<=status0!=FULL || (status1==FULL && base1<base0);
     if(status0!=FULL || (status1==FULL && base1<base0))status1<=PROCESS;else status0<=PROCESS;
     fft_start<=1;read_addr<=0;read_pos<=0;read_crc<=32'hffffffff;phase<=1;
    end
    1:phase<=2;
    2:begin sample<=process_bank ? read1 : read0;phase<=3;end
    3:if(fft_sample_ready)begin read_crc<=process_crc_next;phase<=4;end
    4:begin
     read_crc<=process_crc_next;
     if(read_pos==511)begin
      if(~process_crc_next!=(process_bank ? crc1 : crc0))errors<=errors+1'b1;
      phase<=5;
     end else begin read_pos<=read_pos+1'b1;read_addr<=read_pos+1'b1;phase<=1;end
    end
    5:if(fft_done)phase<=6;
    6:if(result_ready)begin
     if(process_bank)status1<=EMPTY;else status0<=EMPTY;
     completed_windows<=completed_windows+1'b1;phase<=0;
    end
   endcase
  end
 end
endmodule
