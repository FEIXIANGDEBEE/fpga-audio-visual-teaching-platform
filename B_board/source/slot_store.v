`timescale 1ns/1ps
`include "record_binding.vh"
`include "record_params.vh"
// Average groups of 16 samples into PCM8 in SYS RAM before saving.
// Accept only prepared-empty, legacy one-second or new five-second WAV templates.
// Read back every PCM sector before publishing the completed header.
module slot_store #(
 parameter PART=`REC_PARTITION_LBA,RESERVED=`REC_RESERVED,FAT=`REC_FAT_LBA,SPF=`REC_FAT_SECTORS,
 VOLUME_SECTORS=`REC_VOLUME_SECTORS,SPC=`REC_SPC,ROOT_CLUSTER=`REC_ROOT_CLUSTER,SERIAL=`REC_VOLUME_SERIAL,
 BASE=`REC_SLOT_LBA,SECTORS=`REC_SLOT_SECTORS,DIR=`REC_DIRECTORY_LBA,DIR_OFFSET=`REC_DIRECTORY_OFFSET,
 FIRST=`REC_FIRST_CLUSTER,CLUSTERS=`REC_CLUSTER_COUNT,RATE=`REC_SAMPLE_RATE,FIFO_AW=14,
 FRAMES=`BASIC_FRAMES,TEMPLATE="record_template.dath",HEADER_CRC0=`BASIC_CRC0,HEADER_CRC1=`BASIC_CRC1
)(
 input wire clk,rst_n,enabled,start_record,stop_record,
 input wire mic_valid,input wire [34:0] mic_data,input wire mic_alive,mic_warmed,
 output wire start_ready,output reg slot_ready,has_record,output wire [3:0] backend_state,
 output reg [7:0] error_code,output reg saved,output reg [31:0] pcm_bytes,recording_epoch,
 output wire [22:0] recorded_samples,output reg clipped,
 output wire sector_request,output wire [31:0] sector_lba,output wire sector_write,
 input wire sector_ready,sector_accepted,input wire [7:0] sector_data,input wire sector_valid,sector_complete,sector_error,
 input wire [8:0] write_address,output wire [7:0] write_data,output wire quiescent,
 input wire [32:0] card_sectors,input wire media_fault,
 input wire start_load,output reg load_done,
 output wire memory_write,output wire [13:0] memory_address,output wire [7:0] memory_data,input wire [7:0] memory_read,output wire ui_save_committed,output wire [4:0] ui_save_progress
);
 assign ui_save_committed=save_committed;
 // Advance data_page only after the prior sector succeeds. Progress checkpoints
 // are conservative; only header verification completes save.
 assign ui_save_progress=!job_record || !save_committed ? 5'd0:
  op==PCM_WRITE ? {2'd0,data_page[4:2]} :
  op==PCM_VERIFY ? 5'd8+{2'd0,data_page[4:2]} :
  op==COMPLETE_WRITE ? 5'd16 : op==COMPLETE_VERIFY ? 5'd17 : 5'd0;

 localparam IDLE=0,CHECK=1,REQUEST=2,WAIT_IO=3,FINISH=4,CAPTURE=5,BAD_SLOT=6,ERROR=7;
 localparam BPB=0,DIRECTORY=1,HEADER=2,FAT_CHAIN=3,INVALID_WRITE=4,INVALID_VERIFY=5,
  PCM_WRITE=6,COMPLETE_WRITE=7,COMPLETE_VERIFY=8,HEADER_NEW=9,PCM_VERIFY=10,PCM_LOAD=11;
 localparam CW=$clog2(FRAMES+1),FW=$clog2(((FIRST+CLUSTERS-1)>>7)+1);
 reg [2:0] state;reg [3:0] op;reg job_record,job_load,cancelled,fat_copy,bound_complete,save_committed;
 reg [CW-1:0] samples;reg [4:0] data_page;reg bound_new;reg [FW-1:0] fat_page;
 reg [9:0] io_count;reg [23:0] fat_low;reg bad0,bad1;
 reg compare_pending;reg [7:0] compare_data;
 reg [3:0] phase;reg signed [19:0] accumulator;reg have_sequence;reg [15:0] expected_sequence;
 assign recorded_samples=samples;
 assign start_ready=enabled && slot_ready && state==IDLE && mic_alive && mic_warmed;
 assign quiescent=(state==IDLE || state==BAD_SLOT || state==ERROR) && sector_ready;
 assign backend_state=state==ERROR ? 4'd9:state==BAD_SLOT ? 4'd0:
  state==IDLE ? (slot_ready ? 4'd1:4'd0):state==CAPTURE ? 4'd3:
  job_record && save_committed ? 4'd4:4'd2;
 assign sector_request=state==REQUEST && !(job_record && !save_committed && (cancelled || stop_record) && op==INVALID_WRITE);
 assign sector_write=op==INVALID_WRITE || op==PCM_WRITE || op==COMPLETE_WRITE;
 assign sector_lba=op==BPB ? PART:op==DIRECTORY ? DIR:
  op==FAT_CHAIN ? FAT+(fat_copy ? SPF:0)+fat_page:
  (op==PCM_WRITE || op==PCM_VERIFY || op==PCM_LOAD) ? BASE+1+data_page:BASE;
 wire header_tx=op==INVALID_WRITE || op==COMPLETE_WRITE;
 // 512-word pages: empty=0, legacy=1, new=2, BPB=3, directory=4.
 wire [2:0] template_page=op==COMPLETE_WRITE || op==COMPLETE_VERIFY || op==HEADER_NEW ? 3'd2:
  op==BPB ? 3'd3:op==DIRECTORY ? 3'd4:3'd0;
 wire [11:0] template_address={template_page,header_tx ? write_address:io_count[8:0]};
 wire [8:0] expected0,expected1;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),.ADDR_WIDTH_A(12),.ADDR_WIDTH_B(12),
  .DATA_DEPTH_A(4096),.DATA_DEPTH_B(4096),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K"),.INIT_FILE(TEMPLATE)) template_rom(
  .doa(expected0),.dob(expected1),.dia(9'd0),.dib(9'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),
  .clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
  .addra(template_address),.addrb({3'd1,io_count[8:0]}));
 wire exact_header=op==HEADER || op==HEADER_NEW || op==INVALID_VERIFY || op==COMPLETE_VERIFY;
 wire mismatch1=compare_pending && op==HEADER && compare_data!=expected1[7:0];
 wire failed1=bad1 || mismatch1;
 wire [31:0] fat_entry={sector_data,fat_low};
 wire [FW+6:0] fat_cluster={fat_page,7'b0}+io_count[8:2];
 wire gap=have_sequence && mic_data[34:19]!=expected_sequence;
 wire raw_ok=state==CAPTURE && !stop_record && !cancelled && mic_valid && mic_alive && mic_warmed &&
  !gap && mic_data[18:17]==1;
 wire capture_write=raw_ok && phase==15;
 // Recording applies x2 before PCM8 quantization; MIC/voice gain is separate.
 // Preload +1024 at each block start. The first 15 sums fit signed 20 bits;
 // the sixteenth uses 21 bits: [-523264,525296], giving q in [-256,256].
 // Round once, ties toward +infinity, then saturate both ends before encoding.
 wire signed [20:0] block_sum=$signed({accumulator[19],accumulator})+$signed({{5{mic_data[15]}},mic_data[15:0]});
 wire signed [20:0] signed_pcm=block_sum >>> 11;
 wire capture_clip=signed_pcm>21'sd127 || signed_pcm< -21'sd128;
 wire [7:0] capture_pcm=signed_pcm>21'sd127 ? 8'hff:
  signed_pcm< -21'sd128 ? 8'h00:(signed_pcm[7:0]^8'h80);
 wire [13:0] capture_address=samples;
 wire [13:0] pcm_read_address={data_page,op==PCM_VERIFY ? io_count[8:0]:write_address};wire [7:0] pcm_q;
 wire [13:0] load_address={data_page,io_count[8:0]};
 wire [13:0] stored_frames=bound_new ? FRAMES:4002;
 wire load_write=state==WAIT_IO && op==PCM_LOAD && sector_valid && load_address<stored_frames;
 wire [13:0] ram_sys_address=state==CAPTURE ? capture_address:op==PCM_LOAD ? load_address:pcm_read_address;
 reg tail_q,pad_q;
 always @(posedge clk)begin tail_q<=pcm_read_address>=FRAMES;pad_q<=pcm_read_address==FRAMES;end
 assign memory_write=capture_write || load_write;
 assign memory_address=ram_sys_address;
 assign memory_data=op==PCM_LOAD ? sector_data:capture_pcm;
 assign pcm_q=memory_read;
 wire [7:0] expected_pcm=tail_q ? ((FRAMES%2)!=0 && pad_q ? 8'd0:8'h80):pcm_q;
 wire mismatch0=compare_pending && (op==PCM_VERIFY ? compare_data!=expected_pcm:
  (exact_header || expected0[8]) && compare_data!=expected0[7:0]);
 wire failed0=bad0 || mismatch0;
 assign write_data=header_tx ? expected0[7:0]:expected_pcm;
 task fail;input [7:0] code;begin
  state<=ERROR;error_code<=code;slot_ready<=0;job_record<=0;job_load<=0;accumulator<=20'sd1024;phase<=0;
  if(save_committed || code<8'h40 || code==8'h70)begin has_record<=0;pcm_bytes<=0;end
 end endtask
 task request_op;input [3:0] value;begin op<=value;state<=REQUEST;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;op<=BPB;job_record<=0;job_load<=0;load_done<=0;cancelled<=0;save_committed<=0;fat_copy<=0;bound_complete<=0;bound_new<=0;samples<=0;data_page<=0;fat_page<=0;
   io_count<=0;fat_low<=0;bad0<=0;bad1<=0;compare_pending<=0;compare_data<=0;
   phase<=0;accumulator<=20'sd1024;have_sequence<=0;expected_sequence<=0;slot_ready<=0;has_record<=0;
   error_code<=0;saved<=0;pcm_bytes<=0;recording_epoch<=0;clipped<=0;
  end else begin
   saved<=0;load_done<=0;
   if(stop_record && (job_record || job_load) && !save_committed)cancelled<=1;
   if(sector_request && sector_ready && op==INVALID_WRITE)begin save_committed<=1;has_record<=0;pcm_bytes<=0;end
   compare_pending<=state==WAIT_IO && sector_valid && !sector_write && op!=FAT_CHAIN && op!=PCM_LOAD;
   if(sector_valid)compare_data<=sector_data;
   if(mismatch0)bad0<=1;if(mismatch1)bad1<=1;
   if(state==WAIT_IO && sector_valid && !sector_write)begin
    io_count<=io_count+1'b1;
    if(op==FAT_CHAIN)begin
     fat_low<={sector_data,fat_low[23:8]};
     if(io_count[1:0]==3 && fat_cluster>=FIRST && fat_cluster<FIRST+CLUSTERS)begin
      if(fat_cluster==FIRST+CLUSTERS-1)begin if((fat_entry&32'h0fffffff)<32'h0ffffff8)bad0<=1;end
      else if((fat_entry&32'h0fffffff)!=fat_cluster+1'b1)bad0<=1;
     end
    end
   end
   case(state)
    IDLE:if(!enabled)slot_ready<=0;
     else if(!slot_ready || start_record || start_load)begin job_record<=start_record && start_ready;job_load<=start_load && has_record;cancelled<=0;save_committed<=0;state<=CHECK;end
    CHECK:if(DIR_OFFSET>480 || DIR_OFFSET%32!=0 || BASE+SECTORS>card_sectors || PART+VOLUME_SECTORS>card_sectors ||
      FRAMES<1 || FRAMES>16384 || FRAMES>(SECTORS-1)*512 || SECTORS!=CLUSTERS*SPC)begin
      state<=BAD_SLOT;error_code<=8'h10;has_record<=0;job_record<=0;
     end else request_op(BPB);
    REQUEST:if(job_record && !save_committed && (cancelled || stop_record) && op==INVALID_WRITE)begin job_record<=0;state<=IDLE;end
     else if(sector_accepted)begin io_count<=0;bad0<=0;bad1<=0;state<=WAIT_IO;end
    WAIT_IO:if(sector_error)fail(8'h20);else if(sector_complete)state<=FINISH;
    FINISH:if(!sector_write && io_count!=512)fail(8'h21);
     else if((job_record || job_load) && !save_committed && (cancelled || stop_record))begin job_record<=0;job_load<=0;state<=IDLE;end
     else case(op)
      BPB:if(failed0)fail(8'h11);else request_op(DIRECTORY);
      DIRECTORY:if(failed0)fail(8'h12);else request_op(HEADER);
      HEADER:if(failed0 && failed1)request_op(HEADER_NEW);else begin
       bound_complete<=!failed1;bound_new<=0;fat_page<=FIRST>>7;fat_copy<=0;request_op(FAT_CHAIN);
      end
      HEADER_NEW:if(failed0)fail(8'h13);else begin
       bound_complete<=1;bound_new<=1;fat_page<=FIRST>>7;fat_copy<=0;request_op(FAT_CHAIN);
      end
      FAT_CHAIN:if(failed0)fail(8'h14);
       else if(fat_page==((FIRST+CLUSTERS-1)>>7))begin
        if(!fat_copy)begin fat_copy<=1;fat_page<=FIRST>>7;request_op(FAT_CHAIN);end
        else begin slot_ready<=1;has_record<=bound_complete;pcm_bytes<=bound_complete ? (bound_new ? FRAMES:4002):0;error_code<=0;recording_epoch<=1;
         if(job_record)begin samples<=0;phase<=0;accumulator<=20'sd1024;have_sequence<=0;clipped<=0;state<=CAPTURE;end
         else if(job_load && bound_complete)begin data_page<=0;request_op(PCM_LOAD);end
         else begin job_load<=0;state<=IDLE;end
        end
       end else begin fat_page<=fat_page+1'b1;request_op(FAT_CHAIN);end
      INVALID_WRITE:request_op(INVALID_VERIFY);
      INVALID_VERIFY:if(failed0)fail(8'h22);else begin data_page<=0;request_op(PCM_WRITE);end
      PCM_WRITE:if(data_page==(FRAMES+511)/512-1)begin data_page<=0;request_op(PCM_VERIFY);end
       else begin data_page<=data_page+1'b1;request_op(PCM_WRITE);end
      PCM_VERIFY:if(failed0)fail(8'h24);
       else if(data_page==(FRAMES+511)/512-1)request_op(COMPLETE_WRITE);
       else begin data_page<=data_page+1'b1;request_op(PCM_VERIFY);end
      COMPLETE_WRITE:request_op(COMPLETE_VERIFY);
      COMPLETE_VERIFY:if(failed0)fail(8'h22);
       else begin has_record<=1;pcm_bytes<=FRAMES;saved<=1;job_record<=0;state<=IDLE;end
      PCM_LOAD:if(data_page==(bound_new ? (FRAMES+511)/512-1:(4002+511)/512-1))begin load_done<=1;job_load<=0;state<=IDLE;end
       else begin data_page<=data_page+1'b1;request_op(PCM_LOAD);end
      default:fail(8'hff);
     endcase
    CAPTURE:if(cancelled || stop_record)begin job_record<=0;accumulator<=20'sd1024;phase<=0;state<=IDLE;end
     else if(!mic_alive || !mic_warmed)fail(8'h42);
     else if(mic_valid && (gap || mic_data[18:17]!=1))fail(8'h43);
     else if(raw_ok)begin
      have_sequence<=1;expected_sequence<=mic_data[34:19]+16'd1;phase<=phase+1'b1;accumulator<=phase==15 ? 20'sd1024:block_sum[19:0];
      if(mic_data[16] || (capture_write && capture_clip))clipped<=1;
      if(capture_write)begin samples<=samples+1'b1;if(samples==FRAMES-1)begin data_page<=0;request_op(INVALID_WRITE);end end
     end
    BAD_SLOT,ERROR:if(!enabled)begin state<=IDLE;slot_ready<=0;job_record<=0;job_load<=0;end
    default:fail(8'hff);
   endcase
   if(media_fault && enabled && state!=ERROR)fail(8'h70);
  end
 end
endmodule
