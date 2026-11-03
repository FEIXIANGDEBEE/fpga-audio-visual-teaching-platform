`timescale 1ns/1ps
// Standard NEC: 8-bit address, with address and command complement checks.
module ir_nec_rx #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,ms_tick,ir_rx,
 output reg frame_valid,repeat_valid,output reg [7:0] address,command,
 output wire held_valid,output reg [7:0] frames,repeats,errors
);
 localparam UC=CLK_HZ/1000000, UW=UC<2?1:$clog2(UC);
 localparam IDLE=0,HEAD_LOW=1,HEAD_HIGH=2,BIT_LOW=3,BIT_HIGH=4,TAIL=5,REPEAT_TAIL=6;
 (* ASYNC_REG="TRUE" *) reg ir_meta,ir_sync;
 reg previous;reg [UW-1:0] divider;reg [13:0] span;reg [2:0] state;
 reg [4:0] bit_index;reg [31:0] bits;reg linked;reg [7:0] age_ms;
 wire us_tick=divider==UC-1;
 wire [14:0] elapsed={1'b0,span}+(us_tick ? 15'd1:15'd0);
 wire rise=!previous && ir_sync,fall=previous && !ir_sync,edge_seen=rise || fall;
 assign held_valid=linked && age_ms<150;
 task reject;begin state<=IDLE;linked<=0;errors<=errors+1'b1;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   ir_meta<=1;ir_sync<=1;previous<=1;divider<=0;span<=0;state<=IDLE;bit_index<=0;bits<=0;
   linked<=0;age_ms<=150;address<=0;command<=0;frame_valid<=0;repeat_valid<=0;frames<=0;repeats<=0;errors<=0;
  end else begin
   ir_meta<=ir_rx;ir_sync<=ir_meta;previous<=ir_sync;frame_valid<=0;repeat_valid<=0;
   if(us_tick)divider<=0;else divider<=divider+1'b1;
   if(edge_seen)span<=0;else if(us_tick && span<12000)span<=span+1'b1;
   if(ms_tick && age_ms<150)age_ms<=age_ms+1'b1;
   if(ms_tick && age_ms>=149)linked<=0;
   if(state!=IDLE && span>=12000)reject;
   else if(edge_seen)case(state)
    IDLE:if(fall)state<=HEAD_LOW;
    HEAD_LOW:if(rise && elapsed>=8000 && elapsed<=10000)state<=HEAD_HIGH;else reject;
    HEAD_HIGH:if(fall && elapsed>=3500 && elapsed<=5500)begin bit_index<=0;state<=BIT_LOW;end
     else if(fall && elapsed>=1700 && elapsed<=2800)state<=REPEAT_TAIL;else reject;
    BIT_LOW:if(rise && elapsed>=350 && elapsed<=800)state<=BIT_HIGH;else reject;
    BIT_HIGH:if(fall && ((elapsed>=350 && elapsed<=900)||(elapsed>=1300 && elapsed<=2100)))begin
     // NEC sends LSB first; 32 right shifts leave the first bit at bits[0].
     bits<={elapsed>=1300,bits[31:1]};
     if(bit_index==31)state<=TAIL;else begin bit_index<=bit_index+1'b1;state<=BIT_LOW;end
    end else reject;
    TAIL:if(rise && elapsed>=350 && elapsed<=800 && (bits[7:0]^bits[15:8])==8'hff && (bits[23:16]^bits[31:24])==8'hff)begin
     address<=bits[7:0];command<=bits[23:16];frame_valid<=1;frames<=frames+1'b1;linked<=1;age_ms<=0;state<=IDLE;
    end else reject;
    REPEAT_TAIL:if(rise && elapsed>=350 && elapsed<=800 && held_valid)begin
     repeat_valid<=1;repeats<=repeats+1'b1;age_ms<=0;state<=IDLE;
    end else reject;
    default:reject;
   endcase
  end
 end
endmodule
