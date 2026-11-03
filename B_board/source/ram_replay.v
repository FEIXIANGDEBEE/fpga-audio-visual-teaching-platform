`timescale 1ns/1ps
// The synchronous RAM read has a full audio frame to settle after an address change.
module ram_replay #(parameter NEW_FRAMES=15168,LEGACY_FRAMES=4002)(
 input wire clk,rst_n,command_valid,input wire command,output wire command_ack,
 input wire stop,frame_boundary,take,output reg [13:0] address,input wire [7:0] pcm,
 output wire selected,valid,output wire [31:0] frame,output wire begin_pulse
);
 localparam IDLE=0,PRIME=1,RUN=2,DRAIN=3,ACK=4;
 reg [2:0] state;reg [3:0] repetition;
 wire last_repeat=repetition==(command ? 4'd15:4'd11);
 // Replay gain x2: clamp(512*s), where s is offset-binary PCM8 with its sign bit flipped.
 // |s|<=63 is exact, -64 gives -32768, and s>=64 clips to 32767.
 wire [7:0] s={~pcm[7],pcm[6:0]};
 wire [15:0] expanded=s[7]!=s[6] ? (s[7] ? 16'h8000:16'h7fff):{s[6:0],9'd0};
 assign frame={expanded,expanded};
 assign selected=state==PRIME || state==RUN || state==DRAIN;
 assign valid=state==RUN && !stop;
 assign command_ack=state==ACK;
 assign begin_pulse=state==PRIME && frame_boundary && !stop;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;address<=0;repetition<=0;end
  else case(state)
   IDLE:begin address<=0;repetition<=0;if(command_valid)state<=PRIME;end
   PRIME:if(frame_boundary)state<=stop ? ACK:RUN;
   RUN:if(frame_boundary && stop)state<=ACK;
    else if(take)begin
     if(last_repeat)begin
      repetition<=0;
      if(command ? address==NEW_FRAMES-1:address==LEGACY_FRAMES-1)state<=DRAIN;else address<=address+1'b1;
     end else repetition<=repetition+1'b1;
    end
   DRAIN:if(frame_boundary)state<=ACK;
   ACK:if(!command_valid)state<=IDLE;
   default:state<=IDLE;
  endcase
 end
endmodule
