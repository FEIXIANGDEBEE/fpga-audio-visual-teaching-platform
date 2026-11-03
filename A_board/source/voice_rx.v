`timescale 1ns/1ps
// Hold the CRC-qualified packet until every synchronous payload read completes.
// A owns recognition; B owns playback and one-shot actions.
module voice_rx(input wire clk,rst_n,cancel,input wire [31:0] active_epoch,
 input wire packet_valid,input wire [7:0] kind,flags,input wire [31:0] packet_epoch,offset,
 input wire [9:0] length,output wire packet_ready,output wire [8:0] address,input wire [7:0] data,
 output reg reply_pending,output wire [31:0] reply_control,input wire reply_take,
 output wire [7:0] reply_flags,output wire [255:0] diagnostics,
 output reg end_known,output reg [31:0] end_start,input wire [31:0] now_ms,output reg output_mute,output_pause);
 reg open,capture;reg [31:0] control,age,counter;
 reg [2:0] state;reg [5:0] index;reg [159:0] header;
 reg bad,load_begin,load_valid,frame_valid;reg [3:0] load_index;reg [7:0] load_data;
 reg [31:0] sequence;reg consumed;reg reply_ok;reg [1:0] reply_command;
 wire recognized,rejected,invalid,speech,busy,end_candidate,end_good,end_bad;
 wire [7:0] command,denominator;wire [17:0] cost;
 wire [31:0] event_generation,event_control,event_sequence,utterances,rejections,invalidations,drops,cycles;
 wire live=open && capture && age<10000000;
 assign address={3'd0,index};
 assign packet_ready=kind!=8'he9 || state==4;
 assign reply_control=control;
 assign reply_flags={5'd0,reply_ok,reply_command};
 wire frame_ok=header[159:128]==32'h03011003 && !bad && header[31:0]==control;
 voice_utterance utterance(.clk(clk),.rst_n(rst_n),.enable(live && !consumed),.cancel(cancel || !live),
 .frame_valid(frame_valid),.frame_ok(frame_ok),.frame_sequence(sequence),.frame_generation(header[127:96]),
 .frame_control(header[31:0]),.frame_energy(header[63:32]),.load_begin(load_begin),.load_valid(load_valid),.load_index(load_index),.load_data(load_data),
 .event_valid(recognized),.event_command(command),.event_generation(event_generation),.event_control(event_control),.event_last_sequence(event_sequence),
 .event_cost(cost),.event_denominator(denominator),.busy(busy),.utterances(utterances),.rejections(rejections),.invalidations(invalidations),.busy_drops(drops),
 .last_cycles(cycles),.invalid_frame(invalid),.speech_active(speech),.reject_pulse(rejected),.end_candidate(end_candidate),.end_good(end_good),.end_bad(end_bad));
 assign diagnostics={32'h040a0005,control,{24'd0,open,capture,live,busy,speech,consumed,reply_pending,reply_ok},utterances,rejections,invalidations,drops,cycles};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   open<=0;capture<=0;control<=0;age<=0;counter<=0;state<=0;index<=0;header<=0;bad<=0;
   load_begin<=0;load_valid<=0;load_index<=0;load_data<=0;frame_valid<=0;sequence<=0;consumed<=0;
   reply_pending<=0;reply_ok<=0;reply_command<=0;end_known<=0;end_start<=0;output_mute<=1;output_pause<=1;
  end else begin
   counter<=counter+1'b1;load_begin<=0;load_valid<=0;frame_valid<=0;
   if(age<10000000)age<=age+1'b1;
   if(reply_take)reply_pending<=0;
   if(packet_valid && kind==8'he8 && packet_epoch==active_epoch)begin
    age<=0;open<=flags[0];capture<=flags[1];output_mute<=flags[3];output_pause<=flags[4];
    if(offset!=control || !flags[0])begin consumed<=0;reply_pending<=0;end_known<=0;end
    control<=offset;
   end
   case(state)
    0:if(packet_valid && kind==8'he9)begin
     index<=0;header<=0;bad<=length!=36 || packet_epoch!=active_epoch || !live;sequence<=offset;state<=1;
    end
    1:state<=2;
    2:begin
     if(index<20)header[159-index*8 -:8]<=data;
     if(index==19)load_begin<=1;
     if(index>=20)begin load_valid<=1;load_index<=index-20;load_data<=data;if((index==20 && data!=0) || (data!=0 && data<8'hc0))bad<=1;end
     if(index==35)state<=3;else begin index<=index+1'b1;state<=1;end
    end
    3:begin frame_valid<=1;state<=4;end
    4:if(!packet_valid)state<=0;
   endcase
   if(end_candidate && live)begin end_known<=1;end_start<=now_ms;end
   if(end_bad)end_known<=0;
   if(!consumed && live && recognized && event_control==control)begin
    consumed<=1;reply_pending<=1;reply_ok<=command>=1 && command<=3;reply_command<=command[1:0];
   end else if(!consumed && live && rejected)begin consumed<=1;reply_pending<=1;reply_ok<=0;reply_command<=0;end
   if(cancel)begin open<=0;capture<=0;consumed<=1;reply_pending<=0;end_known<=0;end
  end
 end
endmodule
