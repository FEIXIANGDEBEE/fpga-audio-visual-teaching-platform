`timescale 1ns/1ps
// A commit means one completed measurement. Qualify the displayed result
// without changing measurement values or thresholds.
module filter_display(
 input wire clk,rst_n,input wire [31:0] epoch,input wire [3:0] context_id,
 input wire eligible,input wire [2:0] unavailable_status,
 input wire commit,input wire [12:0] record,
 output wire [12:0] display_record,output reg [1:0] confirmations,
 output wire pending,output reg [15:0] commits
);
 reg [31:0] seen_epoch;reg [3:0] seen_context;reg [2:0] candidate;
 reg [12:0] held_record;
 wire identity_change=epoch!=seen_epoch || context_id!=seen_context;
 wire [2:0] status=record[12:10];
 wire accepted_commit=commit && record[3:0]==context_id;
 // Apply live disqualification and identity changes immediately, so a frame
 // latch on the same edge cannot keep the previous context's number.
 assign display_record=!rst_n ? {3'd7,10'd0}:
  identity_change || !eligible ? {identity_change && eligible ? 3'd5:unavailable_status,6'd0,context_id}:
  accepted_commit && status>=4 ? record:
  accepted_commit && status!=held_record[12:10] ? {3'd5,6'd0,context_id}:held_record;
 assign pending=display_record[12:10]==5;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   seen_epoch<=0;seen_context<=0;candidate<=5;confirmations<=0;
   held_record<={3'd7,10'd0};commits<=0;
  end else begin
   seen_epoch<=epoch;seen_context<=context_id;
   if(identity_change || !eligible)begin
    candidate<=5;confirmations<=0;
    held_record<={identity_change && eligible ? 3'd5:unavailable_status,6'd0,context_id};
   end else if(commit && record[3:0]==context_id)begin
    commits<=commits+1'b1;
    if(status==4 || status>=6)begin
     candidate<=status;confirmations<=0;held_record<=record;
    end else if(status==5)begin
     candidate<=5;confirmations<=0;held_record<={3'd5,6'd0,context_id};
    end else begin
     candidate<=status;
     if(candidate!=status || confirmations==0)begin
      confirmations<=1;
      // Remove the numeric result immediately on an invalid measurement.
      held_record<={3'd5,6'd0,context_id};
     end else begin
      if(confirmations<3)confirmations<=confirmations+1'b1;
      if(confirmations>=2)held_record<=record;
      else held_record<={3'd5,6'd0,context_id};
     end
    end
   end
  end
 end
endmodule
