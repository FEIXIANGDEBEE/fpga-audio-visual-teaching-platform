`timescale 1ns/1ps
// prepare starts at FFT completion; commit publishes the prepared level on rr.
module play_level #(parameter integer PEAK_WINDOWS=32)(
 input wire clk,rst_n,start,sample_valid,input wire signed [15:0] sample,
 input wire commit,held,invalidate,input wire [6:0] identity,
 output reg [4:0] level,peak,output reg clipped,valid,input wire prepare);
 reg [15:0] window_peak,envelope,peak_value;
 reg [5:0] peak_age;reg [6:0] old_identity;reg old_held;
 wire [15:0] magnitude=sample[15] ? (~$unsigned(sample)+16'd1):$unsigned(sample);
 wire clear_state=!held && (invalidate || identity!=old_identity || old_held);
 reg [2:0] phase;reg [1:0] selected;
 reg [15:0] prepared_window,prepared_envelope,prepared_peak,difference,saved_envelope,candidate;
 reg [5:0] prepared_age;
 reg rising,prepared_reset,prepared_ready;
 reg [4:0] raw_cells,level_cells,peak_cells;
 wire [15:0] release_step=(difference>>4)==0 ? 16'd1:(difference>>4);
 wire [15:0] peak_step=(peak_value>>4)==0 ? 16'd1:(peak_value>>4);
 wire [15:0] decayed_peak=peak_value==0 ? 16'd0:peak_value-peak_step;
 wire [15:0] cell_value=phase==3 ? prepared_window:selected==0 ? prepared_envelope:prepared_peak;
 wire [4:0] cell_result;wire cell_done;
 wire cell_start=phase==3 || (phase==4 && cell_done && selected!=2);
 level_cells classifier(clk,rst_n,cell_start,cell_value,cell_result,cell_done);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   window_peak<=0;envelope<=0;peak_value<=0;peak_age<=0;old_identity<=0;old_held<=0;
   level<=0;peak<=0;clipped<=0;valid<=0;phase<=0;selected<=0;
   prepared_window<=0;prepared_envelope<=0;prepared_peak<=0;difference<=0;saved_envelope<=0;candidate<=0;
   prepared_age<=0;rising<=0;prepared_reset<=0;prepared_ready<=0;raw_cells<=0;level_cells<=0;peak_cells<=0;
  end else begin
   old_identity<=identity;old_held<=held;
   if(start)window_peak<=0;
   if(sample_valid && (!start || magnitude!=0))begin
    if(start || magnitude>window_peak)window_peak<=magnitude;
   end
   if(clear_state)begin
    envelope<=0;peak_value<=0;peak_age<=0;level<=0;peak<=0;clipped<=0;valid<=0;
    prepared_reset<=1;
   end else if(!held && commit)begin
    envelope<=prepared_reset ? prepared_window:prepared_envelope;
    peak_value<=prepared_reset ? prepared_window:prepared_peak;
    peak_age<=prepared_reset ? 6'd0:prepared_age;
    level<=prepared_reset ? raw_cells:level_cells;peak<=prepared_reset ? raw_cells:peak_cells;
    clipped<=prepared_window>=16'd32760;valid<=1;
   end
   if(prepare)begin
    prepared_window<=window_peak;saved_envelope<=envelope;difference<=envelope-window_peak;
    rising<=window_peak>=envelope;
    candidate<=window_peak>=peak_value ? window_peak:peak_age<PEAK_WINDOWS ? peak_value:decayed_peak;
    prepared_age<=window_peak>=peak_value ? 6'd0:peak_age<PEAK_WINDOWS ? peak_age+1'b1:peak_age;
    prepared_reset<=clear_state;prepared_ready<=0;phase<=1;
   end else case(phase)
    1:begin prepared_envelope<=rising ? prepared_window:saved_envelope-release_step;phase<=2;end
    2:begin prepared_peak<=candidate<prepared_envelope ? prepared_envelope:candidate;phase<=3;end
    3:begin selected<=0;phase<=4;end
    4:if(cell_done)begin
     case(selected)
      0:begin raw_cells<=cell_result;selected<=1;end
      1:begin level_cells<=cell_result;selected<=2;end
      2:begin peak_cells<=cell_result;prepared_ready<=1;phase<=0;end
     endcase
    end
   endcase
   if(start)begin phase<=0;prepared_ready<=0;end
   // synthesis translate_off
   if(commit && !held && !clear_state && !prepared_ready)$fatal(1,"level commit before exact preparation");
   // synthesis translate_on
  end
 end
endmodule
