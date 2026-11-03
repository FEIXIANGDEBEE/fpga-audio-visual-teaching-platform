`timescale 1ns/1ps
// Fit into 640x480 using three operations on one 22-step restoring divider.
// ready holds the completed geometry until the next load.
module fit_geometry (
    input clk, input rst, input start,
    input [15:0] src_w, input [15:0] src_h,
    output reg busy, output reg ready, output reg invalid,
    output reg [9:0] fit_w, output reg [8:0] fit_h,
    output reg [9:0] left, output reg [8:0] bottom,
    output reg [10:0] qx, output reg [10:0] qy,
    output reg [9:0] rx, output reg [8:0] ry
);
    localparam IDLE=0, DIVIDE=1, SET_X=2, SET_Y=3, FINISH=4;
    reg [2:0] state;
    reg [1:0] operation;
    reg [4:0] remaining;
    reg [10:0] width_r, height_r;
    reg wide;
    reg [21:0] dividend;
    // 1 <= divisor <= 2047; every step retains remainder < divisor.
    reg [10:0] divisor, remainder;
    wire [11:0] trial = {remainder, dividend[21]};
    wire take = trial >= {1'b0, divisor};
    wire [10:0] remainder_next = take ? trial - {1'b0,divisor} : trial;
    wire [21:0] quotient_next = {dividend[20:0], take};
    // Keep these products 22 bits wide; the maximum is 1,310,080.
    wire [21:0] w480 = {11'd0,src_w[10:0]} * 22'd480;
    wire [21:0] h640 = {11'd0,src_h[10:0]} * 22'd640;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=IDLE; busy<=0; ready<=0; invalid<=0;
            fit_w<=0; fit_h<=0; left<=0; bottom<=0;
            qx<=0; qy<=0; rx<=0; ry<=0;
            width_r<=0; height_r<=0; wide<=0;
            operation<=0; remaining<=0; dividend<=0; divisor<=0; remainder<=0;
        end else if (start && !busy) begin
            ready<=0; invalid<=0;
            fit_w<=0; fit_h<=0; left<=0; bottom<=0;
            qx<=0; qy<=0; rx<=0; ry<=0;
            if (src_w==0 || src_h==0 || src_w>2047 || src_h>2047) begin
                invalid<=1; busy<=0; state<=IDLE;
            end else begin
                width_r<=src_w[10:0]; height_r<=src_h[10:0];
                wide<=w480>=h640;
                // wide: H*640/W. tall: W*480/H.
                dividend<=w480>=h640 ? h640 : w480;
                divisor<=w480>=h640 ? src_w[10:0] : src_h[10:0];
                remainder<=0; remaining<=22; operation<=0;
                busy<=1; state<=DIVIDE;
            end
        end else begin
            case (state)
                DIVIDE: begin
                    dividend<=quotient_next; remainder<=remainder_next;
                    remaining<=remaining-1'b1;
                    if (remaining==1) begin
                        case (operation)
                            0: begin
                                fit_w<=wide ? 10'd640 : (quotient_next==0 ? 10'd1 : quotient_next[9:0]);
                                fit_h<=wide ? (quotient_next==0 ? 9'd1 : quotient_next[8:0]) : 9'd480;
                                state<=SET_X;
                            end
                            1: begin
                                qx<=quotient_next[10:0]; rx<=remainder_next[9:0]; state<=SET_Y;
                            end
                            2: begin
                                qy<=quotient_next[10:0]; ry<=remainder_next[8:0]; state<=FINISH;
                            end
                        endcase
                    end
                end
                SET_X: begin
                    left<=(10'd640-fit_w)>>1;
                    // Storage begins at the bottom row. Assign an odd spare row to the bottom border.
                    bottom<=9'd480-fit_h-((9'd480-fit_h)>>1);
                    dividend<={11'd0,width_r}; divisor<={1'b0,fit_w};
                    remainder<=0; remaining<=22; operation<=1; state<=DIVIDE;
                end
                SET_Y: begin
                    dividend<={11'd0,height_r}; divisor<={2'b0,fit_h};
                    remainder<=0; remaining<=22; operation<=2; state<=DIVIDE;
                end
                FINISH: begin busy<=0; ready<=1; state<=IDLE; end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
