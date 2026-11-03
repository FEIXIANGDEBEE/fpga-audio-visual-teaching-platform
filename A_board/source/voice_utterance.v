`timescale 1ns/1ps
// Collect MIC features in circular utterance RAM and classify serially.
// Busy drops this optional branch; identity changes and invalid frames
// still cancel an in-flight classification.
module voice_utterance(
 input wire clk,rst_n,enable,cancel,frame_valid,frame_ok,
 input wire [31:0] frame_sequence,frame_generation,frame_control,frame_energy,
 input wire load_begin,load_valid,input wire [3:0] load_index,input wire [7:0] load_data,
 output reg event_valid,output reg [7:0] event_command,
 output wire [31:0] event_generation,event_control,event_last_sequence,
 output wire [17:0] event_cost,output wire [7:0] event_denominator,
 output wire busy,output reg [31:0] utterances,rejections,invalidations,busy_drops,
 output reg [31:0] last_cycles,output wire invalid_frame,
 output wire speech_active,output reg reject_pulse,
 output reg end_candidate,end_good,end_bad
);
 localparam LISTEN=0,SPEECH=1,CLASSIFY=2,COOLDOWN=3;
 reg [1:0] state;reg [6:0] write_frame,first_frame,frame_count,history_count;
 reg load_active,load_admitted,load_bad;reg [4:0] load_count;
 reg [1:0] loud;reg [3:0] quiet;reg [4:0] cooldown;
 reg [31:0] peak_data,expected_sequence,last_generation,last_control;
 reg peak_known;
 wire [31:0] peak=peak_known ? peak_data:32'd0;
 reg have_identity,match_pending,match_start,match_abort;
 reg [6:0] match_length;
 reg [31:0] speech_generation,speech_control,speech_last_sequence;
 reg peak_scan,peak_wait;reg [2:0] peak_address;reg [3:0] peak_remaining;
 wire [31:0] next_peak=state==SPEECH && frame_energy>peak ? frame_energy:peak;
 // E < max(max(E,P)>>5,750) == E<750 || E<(P>>5).
 wire quiet_frame=frame_energy<32'd750 || frame_energy<(peak>>5);
 wire identity_bad=have_identity && (frame_sequence!=expected_sequence || frame_generation!=last_generation || frame_control!=last_control);
 wire load_fault=!load_active || load_bad || load_count!=16;
 assign invalid_frame=frame_valid && (!frame_ok || identity_bad || load_fault);
 wire [6:0] next_history=history_count<8 ? history_count+1'b1:7'd8;
 wire [31:0] history_energy;
 wire history_write=enable && !cancel && frame_valid && frame_ok && !identity_bad && !load_fault && load_admitted && state==LISTEN;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(3),.ADDR_WIDTH_B(3),
  .DATA_DEPTH_A(8),.DATA_DEPTH_B(8),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) history_ram(
  .doa(),.dob(history_energy),.dia(frame_energy),.dib(32'd0),.cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),
  .clka(clk),.clkb(clk),.wea(history_write),.web(1'b0),.rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),
  .addra(write_frame[2:0]),.addrb(peak_address));
 wire [10:0] match_address;wire [7:0] match_data;
 wire match_busy,match_done,match_accepted;wire [7:0] match_command,match_denominator;wire [17:0] match_cost;wire [31:0] match_cycles;
 assign busy=state==CLASSIFY;
 assign speech_active=state==SPEECH;
 assign event_generation=speech_generation;assign event_control=speech_control;assign event_last_sequence=speech_last_sequence;
 assign event_cost=match_cost;assign event_denominator=match_denominator;
 // Cancellation clears ownership and blocks RAM writes and matcher actions.
 // peak_data is unused in LISTEN and rebuilt at LISTEN-to-SPEECH; keep
 // the cancel/admit fanout outside its wide update control.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin peak_data<=0;peak_known<=0;end
  else begin
   if(peak_scan && peak_wait && history_energy>peak)begin peak_data<=history_energy;peak_known<=1;end
   if(frame_valid && frame_ok && !identity_bad && !load_fault &&
      state!=CLASSIFY && load_admitted)begin
    case(state)
     LISTEN:if(frame_energy>2000 && loud==2)begin peak_data<=frame_energy;peak_known<=1;end
     SPEECH:begin peak_data<=next_peak;peak_known<=1;end
     COOLDOWN:if((cooldown==0 || cooldown==1) && quiet_frame && quiet>=11)peak_known<=0;
     default:;
    endcase
   end
   if(!enable || cancel)peak_known<=0;
  end
 end
 wire write_byte=enable && !cancel && load_active && load_admitted && state!=CLASSIFY && load_valid && load_count<16 && load_index==load_count[3:0];
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
  .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K")) utterance_ram(
  .doa(),.dob(match_data),.dia(load_data),.dib(8'd0),
  .cea(1'b1),.ceb(1'b1),.ocea(1'b1),.oceb(1'b1),.clka(clk),.clkb(clk),.wea(write_byte),.web(1'b0),
  .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra({write_frame,load_index}),.addrb(match_address));
 voice_dtw matcher(clk,rst_n,match_start,match_abort || cancel || !enable,match_length,first_frame,
  match_address,match_data,match_busy,match_done,match_accepted,match_command,match_cost,match_denominator,match_cycles);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=LISTEN;write_frame<=0;first_frame<=0;frame_count<=0;history_count<=0;load_active<=0;load_admitted<=0;load_bad<=0;load_count<=0;
   loud<=0;quiet<=0;cooldown<=0;expected_sequence<=0;last_generation<=0;last_control<=0;have_identity<=0;
   match_pending<=0;match_start<=0;match_abort<=0;match_length<=0;speech_generation<=0;speech_control<=0;speech_last_sequence<=0;
   peak_scan<=0;peak_wait<=0;peak_address<=0;peak_remaining<=0;
   event_valid<=0;event_command<=0;reject_pulse<=0;end_candidate<=0;end_good<=0;end_bad<=0;
   utterances<=0;rejections<=0;invalidations<=0;busy_drops<=0;last_cycles<=0;
  end else begin
   event_valid<=0;reject_pulse<=0;match_start<=0;match_abort<=0;
   // Register VAD observations without feeding them back into admission.
   end_candidate<=0;end_good<=0;end_bad<=0;
   if(!enable || cancel || invalid_frame || reject_pulse)end_bad<=1;
   else if(frame_valid && state!=CLASSIFY && load_admitted)begin
    if((state==LISTEN && frame_energy>2000 && loud==2) || (state==SPEECH && !quiet_frame))end_candidate<=1;
    if(state==SPEECH && quiet_frame && quiet==11 && frame_count+1'b1-12>=8)end_good<=1;
    if(state==SPEECH && ((quiet_frame && quiet==11 && frame_count+1'b1-12<8) || (!(quiet_frame && quiet==11) && frame_count==95)))end_bad<=1;
   end
   if(peak_scan)begin
    if(!peak_wait)peak_wait<=1;
    else begin
     if(peak_remaining==1)peak_scan<=0;
     else begin peak_remaining<=peak_remaining-1'b1;peak_address<=peak_address+1'b1;peak_wait<=0;end
    end
   end
   if(load_begin)begin load_active<=1;load_admitted<=state!=CLASSIFY;load_bad<=0;load_count<=0;end
   if(load_valid && load_active)begin
    if(load_count>=16 || load_index!=load_count[3:0])load_bad<=1;
    if(load_count<17)load_count<=load_count+1'b1;
   end
   if(frame_valid)load_active<=0;
   if(!enable || cancel)begin
    state<=LISTEN;load_active<=0;history_count<=0;frame_count<=0;loud<=0;quiet<=0;cooldown<=0;have_identity<=0;match_pending<=0;match_abort<=1;peak_scan<=0;
   end else begin
    if(match_pending)begin match_pending<=0;match_start<=1;end
    if(match_done && state==CLASSIFY && !invalid_frame)begin
     last_cycles<=match_cycles;state<=COOLDOWN;cooldown<=24;quiet<=0;history_count<=0;
     if(match_accepted)begin
      event_valid<=1;event_command<=match_command;
     end else begin rejections<=rejections+1'b1;reject_pulse<=1;end
    end
    if(frame_valid)begin
     expected_sequence<=frame_sequence+1'b1;last_generation<=frame_generation;last_control<=frame_control;have_identity<=1;
     if(!frame_ok || identity_bad || load_fault)begin
      state<=COOLDOWN;cooldown<=24;quiet<=0;loud<=0;history_count<=0;frame_count<=0;match_pending<=0;match_abort<=1;
      invalidations<=invalidations+1'b1;
      peak_scan<=0;
     end else if(state==CLASSIFY || !load_admitted)busy_drops<=busy_drops+1'b1;
     else begin
      write_frame<=write_frame+1'b1;
      case(state)
       LISTEN:begin
        history_count<=next_history;
        loud<=frame_energy>2000 ? loud+1'b1:2'd0;
        if(frame_energy>2000 && loud==2)begin
         state<=SPEECH;first_frame<=write_frame-next_history+1'b1;frame_count<=next_history;quiet<=0;
         peak_scan<=1;peak_wait<=0;peak_address<=write_frame-next_history+1'b1;peak_remaining<=next_history[3:0];
         speech_generation<=frame_generation;speech_control<=frame_control;
        end
       end
       SPEECH:begin
        frame_count<=frame_count+1'b1;quiet<=quiet_frame ? quiet+1'b1:4'd0;
        if(quiet_frame && quiet==11)begin
         if(frame_count+1'b1-12<8)begin state<=COOLDOWN;cooldown<=24;quiet<=0;loud<=0;history_count<=0;rejections<=rejections+1'b1;reject_pulse<=1;end
         else begin
          match_length<=frame_count+1'b1-12;speech_last_sequence<=frame_sequence-12;match_pending<=1;state<=CLASSIFY;utterances<=utterances+1'b1;
         end
        end else if(frame_count==95)begin state<=COOLDOWN;cooldown<=24;quiet<=0;loud<=0;history_count<=0;rejections<=rejections+1'b1;reject_pulse<=1;end
       end
       COOLDOWN:begin
        if(cooldown!=0)cooldown<=cooldown-1'b1;
        quiet<=quiet_frame ? (quiet<12 ? quiet+1'b1:quiet):4'd0;
        if((cooldown==0 || cooldown==1) && quiet_frame && quiet>=11)begin state<=LISTEN;quiet<=0;loud<=0;history_count<=0;end
       end
      endcase
     end
    end
   end
  end
 end
endmodule
