`timescale 1ns/1ps
// The two SYS stages carry position and song identity with the quotient.
// Stage one decides 8/4 seconds; stage two decides 2/1. UART uses the same sample.
module play_progress #(parameter integer RATE=48000,FRAMES=672000)(
 input wire clk,rst_n,music,input wire [1:0] song,input wire loading,ready,
 input wire [31:0] position,loops,input wire [66:0] record,input wire [31:0] expected_generation,
 output wire [1:0] state,output wire [3:0] seconds,segments,output wire [255:0] diagnostic_row
);
 wire qualified=!loading && ready && record[0] && record[2:1]==song &&
  record[66:35]==expected_generation && record[34:3]==FRAMES && position<FRAMES;
 wire [1:0] raw_state=!music ? 2'd0:qualified ? 2'd2:2'd1;
 wire bit8=position[19:0]>=8*RATE;
 wire [19:0] remainder8=bit8 ? position[19:0]-8*RATE:position[19:0];
 wire bit4=remainder8>=4*RATE;
 wire [19:0] remainder4=bit4 ? remainder8-4*RATE:remainder8;
 reg [17:0] remainder1;reg [1:0] high1,state1,state2,song1,song2;
 reg [3:0] seconds2,segments2;
 reg [31:0] position1,loops1,expected1,generation1,length1;
 reg [31:0] position2,loops2,expected2,generation2,length2;
 reg [2:0] flags1,flags2;
 reg valid1,valid2;
 wire bit2=remainder1>=2*RATE;
 wire [17:0] remainder2=bit2 ? remainder1-2*RATE:remainder1;
 wire [3:0] quotient={high1,bit2,(remainder2>=RATE)};
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin valid1<=0;valid2<=0;end
  else begin valid1<=1;valid2<=valid1;end
 // valid1/valid2 mask the two startup cycles; data registers need no reset.
 always @(posedge clk)begin
  remainder1<=remainder4[17:0];high1<={bit8,bit4};state1<=raw_state;song1<=song;
  position1<=position;loops1<=loops;expected1<=expected_generation;
  generation1<=record[66:35];length1<=record[34:3];flags1<=record[2:0];
  state2<=state1;song2<=song1;position2<=position1;loops2<=loops1;expected2<=expected1;
  generation2<=generation1;length2<=length1;flags2<=flags1;
  seconds2<=state1==2 ? quotient:4'd0;
  segments2<=state1==2 ? (position1==FRAMES-1 ? 4'd14:quotient):4'd0;
 end
 // Hide a stale song/generation while the replacement result crosses both stages.
 wire current=qualified && valid2 && expected_generation==expected2 && song==song2;
 assign state=!music ? 2'd0:(current && state2==2) ? 2'd2:2'd1;
 assign seconds=state==2 ? seconds2:4'd0;
 assign segments=state==2 ? segments2:4'd0;
 assign diagnostic_row=!valid2 ? {32'h07040001,224'd0}:
  {32'h07040001,{22'd0,state2,seconds2,segments2},position2,loops2,expected2,generation2,length2,{29'd0,flags2}};
endmodule
