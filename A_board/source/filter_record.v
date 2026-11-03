`timescale 1ns/1ps
// grade_record={status[2:0],approximate_dB[5:0],context[3:0]}.
// Keep full measurement identity local for qualification.
module filter_record(
 input wire clk,rst_n,input wire [31:0] epoch,clips,high_pre,high_post,
 input wire [15:0] block_id,input wire record_valid,eligible,
 input wire [3:0] context_id,output wire [1:0] diagnostic,
 output reg [12:0] grade_record,output wire grade_current,output reg grade_strobe
);
 localparam [31:0] P_MIN=32'd4096;
 reg [31:0] seen_epoch,clip_anchor;
 reg [15:0] seen_block_id;
 reg valid_q,pass_q,raw_valid_q;
 reg [1:0] db_state;
 reg db_ready;
 reg [31:0] normalized;
 reg signed [12:0] db_acc;
 function [7:0] mantissa_db;
  input [3:0] m;
  begin case(m)
   0:mantissa_db=9;1:mantissa_db=25;2:mantissa_db=40;3:mantissa_db=55;
   4:mantissa_db=69;5:mantissa_db=82;6:mantissa_db=95;7:mantissa_db=107;
   8:mantissa_db=118;9:mantissa_db=130;10:mantissa_db=140;11:mantissa_db=151;
   12:mantissa_db=160;13:mantissa_db=170;14:mantissa_db=179;default:mantissa_db=188;
  endcase end
 endfunction
 wire signed [12:0] mantissa_q6=$signed({5'd0,mantissa_db(normalized[30:27])});
 wire signed [12:0] rounded_db=db_acc+13'sd32;
 wire new_block=record_valid && block_id!=seen_block_id;
 wire pre_low=high_pre<P_MIN,post_low=high_post<P_MIN;
 wire saturated=high_pre==32'hffffffff || high_post==32'hffffffff;
 wire clipped=clips!=clip_anchor;
 wire ratio_ge_four=high_post[31:30]==0 && high_pre>={high_post[29:0],2'b00};
 wire qualified=eligible && !pre_low && !post_low && !saturated && !clipped;
 wire [2:0] status=saturated || clipped ? 3'd4:pre_low ? 3'd2:post_low ? 3'd3:high_post>high_pre ? 3'd1:3'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   seen_epoch<=0;clip_anchor<=0;seen_block_id<=0;valid_q<=0;pass_q<=0;raw_valid_q<=0;grade_record<={3'd7,10'd0};
   db_state<=0;db_ready<=0;normalized<=0;db_acc<=0;grade_strobe<=0;
  end else if(epoch!=seen_epoch)begin
   seen_epoch<=epoch;clip_anchor<=clips;seen_block_id<=block_id;valid_q<=0;pass_q<=0;raw_valid_q<=0;
   db_state<=0;db_ready<=0;grade_strobe<=0;
  end else if(new_block)begin
   seen_block_id<=block_id;clip_anchor<=clips;
   valid_q<=qualified;pass_q<=qualified && ratio_ge_four;raw_valid_q<=eligible;
   grade_record<={status,6'd0,context_id};
   // The completed pair stays fixed for at least 25600 clocks; conversion needs
   // at most 43. Abort on epoch, block or context change.
   normalized<=high_pre;db_acc<=0;db_state<=status==0 ? 2'd1:2'd0;
   db_ready<=status!=0;grade_strobe<=eligible && status!=0;
  end else begin
   grade_strobe<=0;
   if(!record_valid || !eligible)begin valid_q<=0;pass_q<=0;raw_valid_q<=0;db_state<=0;db_ready<=0;end
   else if(context_id!=grade_record[3:0])begin db_state<=0;db_ready<=0;end
   else case(db_state)
    1:if(!normalized[31])begin normalized<={normalized[30:0],1'b0};db_acc<=db_acc-13'sd193;end
      else begin db_acc<=db_acc+mantissa_q6;normalized<=high_post;db_state<=2;end
    2:if(!normalized[31])begin normalized<={normalized[30:0],1'b0};db_acc<=db_acc+13'sd193;end
      else begin db_acc<=db_acc-mantissa_q6;db_state<=3;end
    3:begin grade_record[9:4]<=rounded_db[11:6];db_ready<=1;grade_strobe<=1;db_state<=0;end
    default:db_state<=0;
   endcase
  end
 end
 wire current_record=epoch==seen_epoch && block_id==seen_block_id;
 wire valid_result=current_record && record_valid && eligible && valid_q;
 assign diagnostic={valid_result,valid_result && pass_q};
 assign grade_current=current_record && record_valid && eligible && raw_valid_q && db_ready && context_id==grade_record[3:0];
endmodule
