`timescale 1ns/1ps
// BMP pixels arrive bottom row first. Reverse row addresses while writing
// 0x00RRGGBB into SDRAM top to bottom. The memory mailbox accepts one word
// at a time, passing backpressure through the scaler to the source FIFO.
module tf_fifo_writer #(
    parameter integer ABORT_ENABLE = 0,
    parameter [20:0] BASE = 21'd614400,
    parameter [9:0] IMAGE_WIDTH = 10'd640,
    parameter [8:0] IMAGE_HEIGHT = 9'd480,
    parameter [18:0] IMAGE_WORDS = 19'd307200
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire        abort,
    input  wire        pixel_valid,
    input  wire [23:0] pixel_rgb,
    output wire        pixel_ready,
    output reg         busy,
    output reg         done_pulse,
    output reg         error,
    output reg  [31:0] words_written,
    output reg  [20:0] first_error_addr,
    output reg  [31:0] max_response_cycles,
    output reg  [31:0] stall_cycles,
    output wire        req_valid,
    output wire        req_write,
    output wire [20:0] req_addr,
    output wire [31:0] req_data,
    output wire [3:0]  req_dm,
    input  wire        req_ready,
    input  wire        rsp_valid,
    input  wire        rsp_error,
    output wire        rsp_ready
);
    reg waiting_response;
    reg [9:0] x;
    reg [8:0] file_row;
    reg [20:0] row_base;
    reg [31:0] response_cycles;
    reg error_seen;

    assign req_valid = busy && !waiting_response && pixel_valid;
    assign req_write = 1'b1;
    assign req_addr = row_base + x;
    assign req_data = {8'h00, pixel_rgb};
    assign req_dm = 4'b0000;
    assign rsp_ready = 1'b1;
    assign pixel_ready = busy && !waiting_response && req_ready;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy<=0; done_pulse<=0; error<=0; words_written<=0;
            first_error_addr<=0; max_response_cycles<=0; stall_cycles<=0;
            waiting_response<=0; x<=0; file_row<=0; row_base<=BASE;
            response_cycles<=0; error_seen<=0;
        end else begin
            done_pulse<=0;
            // Cancel synchronously. Wait for the memory mailbox to drain before
            // starting another ingest transaction.
            if (ABORT_ENABLE && abort) begin
                busy<=0;waiting_response<=0;error<=0;error_seen<=0;
            end else if (start && !busy) begin
                busy<=1; error<=0; error_seen<=0; words_written<=0;
                first_error_addr<=0; max_response_cycles<=0; stall_cycles<=0;
                waiting_response<=0; x<=0; file_row<=0;
                row_base<=BASE + 21'd306560;
                response_cycles<=0;
            end else if (busy) begin
                if (pixel_valid && !pixel_ready) stall_cycles<=stall_cycles+1'b1;
                if (req_valid && req_ready) begin
                    waiting_response<=1;
                    response_cycles<=0;
                end
                if (waiting_response && !rsp_valid && response_cycles!=32'hffffffff)
                    response_cycles<=response_cycles+1'b1;
                if (waiting_response && rsp_valid) begin
                    waiting_response<=0;
                    if (response_cycles>max_response_cycles)
                        max_response_cycles<=response_cycles;
                    if (rsp_error) begin
                        if (!error_seen) first_error_addr<=row_base+x;
                        error<=1; error_seen<=1; busy<=0;
                    end else begin
                        words_written<=words_written+1'b1;
                        if (words_written + 1'b1 == IMAGE_WORDS) begin
                            busy<=0;
                            done_pulse<=1;
                        end else if (x + 1'b1 == IMAGE_WIDTH) begin
                            x<=0;
                            file_row<=file_row+1'b1;
                            row_base<=row_base-IMAGE_WIDTH;
                        end else x<=x+1'b1;
                    end
                end
            end
        end
    end
endmodule
