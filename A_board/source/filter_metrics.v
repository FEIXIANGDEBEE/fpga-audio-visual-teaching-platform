`timescale 1ns/1ps
// Use the qualified 1024-frame projections and integer dB conversion.
// Carry the completed block's epoch, mode and track into its status.
module filter_metrics(input wire clk,rst_n,sample_valid,sample_eligible,eligible,
 input wire signed [15:0] pre,post,input wire [31:0] epoch,clips,
 input wire [3:0] context_id,input wire mute,pause,music,warm,
 output wire fault,output wire [12:0] record,output wire current,
 output wire [15:0] block_id,output wire [31:0] high_pre,high_post,output wire record_commit);
 wire valid,strobe;wire [31:0] low_pre,low_post;wire [12:0] completed;
 audio_metrics projection(clk,rst_n,sample_valid,sample_eligible && eligible,pre,post,epoch,valid,block_id,low_pre,low_post,high_pre,high_post,fault);
 filter_record calculation(clk,rst_n,epoch,clips,high_pre,high_post,block_id,valid,eligible,context_id,,completed,current,strobe);
 // Suppress numbers when live qualification fails. Quiet or muted input
 // cannot establish successful attenuation.
 wire [2:0] status=fault ? 3'd4:mute ? 3'd6:!music ? 3'd7:3'd5;
 assign record=current ? completed:{status,6'd0,context_id};
 assign record_commit=strobe && current;
endmodule
