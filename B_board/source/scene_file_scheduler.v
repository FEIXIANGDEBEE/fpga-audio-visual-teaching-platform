`timescale 1ns/1ps
// Only one byte request may be outstanding. A span retains its owner through
// the next 512-byte file-sector boundary, where active audio regains priority.
// Pausing on a cached byte preserves partial PCM frames. The sector service
// finishes the physical sector before returning byte_valid.
module scene_file_scheduler(
 input wire clk,rst_n,active_bank,
 input wire [2:0] demand,available,
 input wire [31:0] offset0,offset1,offset2,input wire [3:0] file0,file1,file2,
 output wire request,output wire [1:0] owner,output wire [31:0] offset,output wire [3:0] file_id,
 input wire service_ready,service_valid,service_error,input wire [1:0] response_owner,
 output wire audio_accepted,output wire accepted_bank,
 output wire image_accepted,output wire audio_valid,audio_error,response_bank,
 output wire image_valid,image_error,
 output reg protocol_fault,output reg [31:0] served0,served1,served2
);
 reg locked,pending;reg [1:0] span_owner,inflight_owner;
 reg [31:0] previous_offset;reg [3:0] span_file;
 wire [1:0] alternate=active_bank ? 0 : 1;
 wire [31:0] span_offset=span_owner==0 ? offset0 : span_owner==1 ? offset1 : offset2;
 wire [3:0] current_file=span_owner==0 ? file0 : span_owner==1 ? file1 : file2;
 wire continuing=locked && demand[span_owner] && span_offset==previous_offset+1'b1 && current_file==span_file;
 reg [1:0] selected;
 always @*begin
  if(continuing)selected=span_owner;
  else if(demand[active_bank])selected={1'b0,active_bank};
  else if(demand[alternate])selected=alternate;
  else selected=2;
 end
 assign owner=selected;
 assign offset=selected==0 ? offset0 : selected==1 ? offset1 : offset2;
 assign file_id=selected==0 ? file0 : selected==1 ? file1 : file2;
 assign request=!pending && !protocol_fault && demand[selected] && available[selected] && service_ready;
 assign audio_accepted=request && selected<2;assign accepted_bank=selected[0];
 assign image_accepted=request && selected==2;
 wire response_ok=pending && response_owner==inflight_owner;
 assign audio_valid=service_valid && response_ok && inflight_owner<2;
 assign audio_error=service_error && response_ok && inflight_owner<2;
 assign response_bank=inflight_owner[0];
 assign image_valid=service_valid && response_ok && inflight_owner==2;
 assign image_error=service_error && response_ok && inflight_owner==2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin locked<=0;pending<=0;span_owner<=0;inflight_owner<=0;previous_offset<=0;span_file<=0;
   protocol_fault<=0;served0<=0;served1<=0;served2<=0;end
  else begin
   // Recheck priority when bind or loop seek begins a new span.
   if(locked && (!demand[span_owner] || (span_owner==0 ? offset0 : span_owner==1 ? offset1 : offset2)!=previous_offset+1'b1 ||
      (span_owner==0 ? file0 : span_owner==1 ? file1 : file2)!=span_file) && !pending)locked<=0;
   if(request)begin pending<=1;inflight_owner<=selected;span_owner<=selected;span_file<=file_id;previous_offset<=offset;locked<=1;end
   if(service_valid || service_error)begin
    pending<=0;
    if(!response_ok)protocol_fault<=1;
    if(service_error || previous_offset[8:0]==511)locked<=0;
    if(service_valid && response_ok)case(inflight_owner)
     0:served0<=served0+1'b1;1:served1<=served1+1'b1;2:served2<=served2+1'b1;default:protocol_fault<=1;
    endcase
   end
  end
 end
endmodule
