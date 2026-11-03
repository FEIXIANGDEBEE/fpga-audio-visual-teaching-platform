`timescale 1ns/1ps
// Raw-power scratch and format3 conversion run independently of FFT/mapper
// backpressure. Carry an invalid skipped window into the next selected frame
// so stride2 cannot hide a damaged window.
module voice_feature #(parameter DIAG_REPLAY=0)(
 input wire clk,rst_n,enable,input wire band_valid,band_last,input wire [3:0] band_index,input wire [31:0] band_power,
 input wire [2:0] task_context,input wire task_invalid,
 input wire [31:0] task_generation,task_window,live_generation,control_generation,
 input wire [31:0] clips,fft_errors,saturations,discontinuities,window_errors,
 output reg pending,input wire take,input wire [5:0] tx_address,output reg [7:0] tx_data,output reg [31:0] feature_sequence_out,
 output wire [31:0] latest_sequence,
 output reg [31:0] dropped,
 input wire replay_active,replay_begin,replay_byte,replay_commit,input wire [3:0] replay_index,
 input wire [7:0] replay_data,input wire [31:0] replay_energy,
 output wire [31:0] observe_energy,observe_control,output wire observe_invalid
);
 localparam IDLE=0,CAPTURE=1,READ=2,WAIT=3,LOAD=4,SHIFT=5,STORE=6,NORM_READ=7,NORM_WAIT=8,NORM_STORE=9,COMMIT=10;
 reg [3:0] state,index;reg [15:0] seen;reg [31:0] raw_sequence,feature_sequence;
 reg [31:0] held_generation,held_window,held_control,held_sequence;
 reg [31:0] previous_clips,previous_fft,previous_saturations,previous_discontinuities,previous_windows;
 reg invalid,pending_invalid;reg [35:0] total;reg [31:0] work;reg [4:0] exponent;
 reg [7:0] maximum,logarithm,held_flags;reg [31:0] held_energy;
 assign observe_energy=held_energy;
 assign observe_control=held_control;
 assign observe_invalid=held_flags[3];
 wire first=band_valid && band_index==0 && task_context[2];
 wire selected=first && !raw_sequence[0];
 wire counter_change=clips!=previous_clips || fft_errors!=previous_fft || saturations!=previous_saturations || discontinuities!=previous_discontinuities || window_errors!=previous_windows;
 wire replay=DIAG_REPLAY && replay_active;
 reg replay_frame_ok;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)replay_frame_ok<=0;
  else if(!enable || !replay || replay_commit)replay_frame_ok<=0;
  else if(replay_begin)replay_frame_ok<=state==IDLE && !pending;
 wire replay_write=replay && replay_frame_ok && enable && state==IDLE && !pending && replay_byte;
 wire start_frame=enable && !replay && state==IDLE && !pending && selected;
 wire capture_write=enable && band_valid && (state==CAPTURE || start_frame);
 wire [31:0] scratch_data;
 wire [3:0] scratch_write_address=replay_write ? replay_index:state==STORE || state==NORM_STORE ? index:band_index;
 wire [31:0] scratch_write_data=replay_write ? {24'd0,replay_data}:state==NORM_STORE ? {24'd0,normalized}:state==STORE ? {24'd0,logarithm}:band_power;
 wire [3:0] scratch_read_address=pending ? tx_address[3:0]-4'd4:index;
 assign latest_sequence=feature_sequence-1'b1;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(4),.ADDR_WIDTH_B(4),
  .DATA_DEPTH_A(16),.DATA_DEPTH_B(16),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) scratch(
  .doa(),.dob(scratch_data),.dia(scratch_write_data),.dib(32'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),
  .clka(clk),.clkb(clk),.wea(replay_write || capture_write || state==STORE || state==NORM_STORE),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
  .addra(scratch_write_address),.addrb(scratch_read_address));
 wire [7:0] difference=maximum-scratch_data[7:0];
 wire [7:0] normalized=index==0 ? 8'd0:difference>64 ? 8'hc0:(8'd0-difference);
 // Hold TX data in RAM through done. A pending packet blocks this optional
 // branch only; skipped candidates still advance the sequence.
 // RAM read plus byte-mux register supplies the required TX latency.
 always @(posedge clk)begin
  if(tx_address>=20)tx_data<=scratch_data[7:0];
  else case(tx_address)
   0:tx_data<=3;1:tx_data<=1;2:tx_data<=16;3:tx_data<=held_flags;
   4,5,6,7:tx_data<=held_generation[31-tx_address[1:0]*8 -:8];
   8,9,10,11:tx_data<=held_window[31-tx_address[1:0]*8 -:8];
   12,13,14,15:tx_data<=held_energy[31-tx_address[1:0]*8 -:8];
   16,17,18,19:tx_data<=held_control[31-tx_address[1:0]*8 -:8];
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;index<=0;seen<=0;raw_sequence<=0;feature_sequence<=0;held_generation<=0;held_window<=0;held_control<=0;held_sequence<=0;
   previous_clips<=0;previous_fft<=0;previous_saturations<=0;previous_discontinuities<=0;previous_windows<=0;
   invalid<=0;pending_invalid<=0;total<=0;work<=0;exponent<=0;maximum<=0;logarithm<=0;held_flags<=0;held_energy<=0;pending<=0;feature_sequence_out<=0;dropped<=0;
  end else begin
   if(take)pending<=0;
   // Advance for every attempted diagnostic frame, including CRC/timeout failures,
   // so A sees a sequence gap in the next valid packet.
   if(DIAG_REPLAY && replay_begin && enable)begin held_sequence<=feature_sequence;feature_sequence<=feature_sequence+1'b1;end
   if(band_valid && task_context[2] && task_invalid)pending_invalid<=1;
   if(state!=IDLE && (counter_change || task_invalid))invalid<=1;
   if(first)begin
    raw_sequence<=raw_sequence+1'b1;
    previous_clips<=clips;previous_fft<=fft_errors;previous_saturations<=saturations;previous_discontinuities<=discontinuities;previous_windows<=window_errors;
    if(task_invalid || counter_change)pending_invalid<=1;
    if(selected && !replay)feature_sequence<=feature_sequence+1'b1;
    if(enable && !replay && selected && (state!=IDLE || pending))begin dropped<=dropped+1'b1;pending_invalid<=1;end
   end
   if(!enable)begin state<=IDLE;pending_invalid<=1;end
   else if(replay && state==IDLE)begin
    if(replay_begin)begin seen<=0;invalid<=pending;end
    if(replay_byte)begin
     if(replay_write)begin seen[replay_index]<=1;if(seen[replay_index])invalid<=1;end
     else invalid<=1;
    end
    if(replay_commit)begin
     if(replay_frame_ok && seen==16'hffff && !invalid && !pending)begin
      held_generation<=live_generation;held_window<=task_window;held_control<=control_generation;
      held_flags<=8'h03;held_energy<=replay_energy;feature_sequence_out<=held_sequence;
      pending<=1;pending_invalid<=0;
     end else dropped<=dropped+1'b1;
    end
   end else case(state)
    IDLE:if(start_frame)begin
     state<=CAPTURE;seen<=16'd1;invalid<=task_invalid || counter_change || pending_invalid || band_last;pending_invalid<=0;
     held_generation<=task_generation;held_window<=task_window;held_control<=control_generation;held_sequence<=feature_sequence;
     total<=0;maximum<=0;
    end
    CAPTURE:if(band_valid)begin
     seen<=seen | (16'd1<<band_index);invalid<=invalid || task_invalid || seen[band_index] || task_generation!=held_generation || task_window!=held_window;
     if(band_index!=0)total<=total+band_power;
     if(band_last)begin
      if(band_index!=15 || (seen | (16'd1<<band_index))!=16'hffff || seen[band_index])begin state<=IDLE;pending_invalid<=1;dropped<=dropped+1'b1;end
      else begin index<=0;state<=READ;end
     end
    end
    READ:state<=WAIT;
    WAIT:state<=LOAD;
    LOAD:begin work<=scratch_data;exponent<=0;state<=SHIFT;end
    SHIFT:begin
     if(work>=16)begin work<=work>>1;exponent<=exponent+1'b1;end
     else begin
      logarithm<=work>=8 ? {exponent,3'd0}+8'd16+work[7:0] : work>=4 ? 8'd8+{work[5:0],1'b0} : work>=2 ? {work[5:0],2'b00}:8'd0;
      state<=STORE;
     end
    end
    STORE:begin
     if(index!=0 && logarithm>maximum)maximum<=logarithm;
     if(index==15)begin index<=0;state<=NORM_READ;end
     else begin index<=index+1'b1;state<=READ;end
    end
    NORM_READ:state<=NORM_WAIT;
    NORM_WAIT:state<=NORM_STORE;
    NORM_STORE:begin
     if(index==15)state<=COMMIT;else begin index<=index+1'b1;state<=NORM_READ;end
    end
    COMMIT:begin
     if(pending && !take)begin dropped<=dropped+1'b1;pending_invalid<=1;end
     else begin
      held_flags<={4'd0,(invalid || counter_change || task_invalid || held_generation!=live_generation || held_control!=control_generation),3'b011};
      held_energy<=total[35:4];
      feature_sequence_out<=held_sequence;pending<=1;
     end
     state<=IDLE;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
