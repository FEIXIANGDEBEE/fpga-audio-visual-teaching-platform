`timescale 1ns/1ps
// Active-first 640x480 raster: totals 800x525, with active-low sync.
// Horizontal: 640+16+96+48; vertical: 480+10+2+33.
module video_timing_640x480 (
    input  wire       pixel_clk,
    input  wire       reset_n,
    output reg        hsync,
    output reg        vsync,
    output reg        de,
    output reg [9:0]  x,
    output reg [9:0]  y,
    output wire blank_start,
    output reg        frame_start
);
    reg [9:0] h_count, v_count;assign blank_start=h_count==0 && v_count==480;

    always @(posedge pixel_clk or negedge reset_n) begin
        if (!reset_n) begin
            h_count <= 0;
            v_count <= 0;
            hsync   <= 1'b1;
            vsync   <= 1'b1;
            de      <= 1'b0;
            x       <= 10'd0;
            y       <= 10'd0;
            frame_start <= 1'b0;
        end else begin
            if (h_count == 10'd799) begin
                h_count <= 10'd0;
                v_count <= (v_count == 10'd524) ? 10'd0 : (v_count + 10'd1);
            end else begin
                h_count <= h_count + 10'd1;
            end
            hsync <= !(h_count >= 10'd656 && h_count < 10'd752);
            vsync <= !(v_count >= 10'd490 && v_count < 10'd492);
            de    <= (h_count < 10'd640) && (v_count < 10'd480);
            x     <= (h_count < 10'd640) ? h_count : 10'd0;
            y     <= v_count;
            frame_start <= (h_count == 10'd0) && (v_count == 10'd0);
        end
    end
endmodule
