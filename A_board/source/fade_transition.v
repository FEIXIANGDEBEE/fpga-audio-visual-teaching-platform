`timescale 1ns/1ps
// The control domain owns swap requests. The pixel domain changes fade state
// at frame boundaries and commits after a complete black frame, hiding the swap.
module fade_transition #(
    parameter integer FADE_FRAMES = 32,
    parameter integer HOLD_TIMEOUT_FRAMES = 32
) (
    input  wire       ctrl_clk,
    input  wire       ctrl_rst_n,
    input  wire       swap_pending,
    output reg        swap_commit,
    output wire       fade_busy,

    input  wire       pix_clk,
    input  wire       pix_rst_n,
    input  wire       player_active,
    input  wire       frame_start,
    input  wire       swap_ack,
    input  wire [23:0] rgb_in,
    output reg  [23:0] rgb_out,
    output wire       fade_active,
    output wire [8:0] opacity,
    output wire [1:0] phase
);
    localparam integer STEP = (FADE_FRAMES > 0) ? (256 / FADE_FRAMES) : 256;
    localparam integer CNT_W = (FADE_FRAMES <= 2) ? 2 : $clog2(FADE_FRAMES + 1);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_OUT  = 2'd1;
    localparam [1:0] S_HOLD = 2'd2;
    localparam [1:0] S_IN   = 2'd3;

    // Detect the player request and synchronize the black-frame commit back to control.
    reg start_toggle;
    reg swap_pending_d;
    reg busy_ctrl;
    (* ASYNC_REG="TRUE" *) reg commit_sync1, commit_sync2;
    reg commit_seen;
    (* ASYNC_REG="TRUE" *) reg done_sync1, done_sync2;
    reg done_seen;

    // Update ramp only at frame_start; hold alpha_sel through the visible frame.
    reg [1:0] state;
    reg [CNT_W-1:0] ramp;
    reg commit_toggle;
    reg done_toggle;
    reg [7:0] hold_frames;
    reg ack_seen;
    (* ASYNC_REG="TRUE" *) reg start_sync1, start_sync2;
    reg start_seen;
    reg start_waiting;

    // Use 33 rounded smoothstep entries with exact endpoints. Index by frame,
    // so no curve multiplication runs at the pixel rate.
    function [8:0] eased_alpha;
        input integer index;
        begin
            case(index)
                0: eased_alpha=9'd0;
                1: eased_alpha=9'd1;
                2: eased_alpha=9'd3;
                3: eased_alpha=9'd6;
                4: eased_alpha=9'd11;
                5: eased_alpha=9'd17;
                6: eased_alpha=9'd24;
                7: eased_alpha=9'd31;
                8: eased_alpha=9'd40;
                9: eased_alpha=9'd49;
                10: eased_alpha=9'd59;
                11: eased_alpha=9'd70;
                12: eased_alpha=9'd81;
                13: eased_alpha=9'd92;
                14: eased_alpha=9'd104;
                15: eased_alpha=9'd116;
                16: eased_alpha=9'd128;
                17: eased_alpha=9'd140;
                18: eased_alpha=9'd152;
                19: eased_alpha=9'd164;
                20: eased_alpha=9'd175;
                21: eased_alpha=9'd186;
                22: eased_alpha=9'd197;
                23: eased_alpha=9'd207;
                24: eased_alpha=9'd216;
                25: eased_alpha=9'd225;
                26: eased_alpha=9'd232;
                27: eased_alpha=9'd239;
                28: eased_alpha=9'd245;
                29: eased_alpha=9'd250;
                30: eased_alpha=9'd253;
                31: eased_alpha=9'd255;
                32: eased_alpha=9'd256;
                default:eased_alpha=9'd256;
            endcase
        end
    endfunction
    wire [8:0] ramp_alpha = eased_alpha((ramp * 32) / FADE_FRAMES);
    wire [8:0] alpha_now;
    assign alpha_now = (state == S_IDLE) ? 9'd256 :
                       (state == S_HOLD) ? 9'd0  :
                       ((state == S_OUT) && (ramp == FADE_FRAMES)) ? 9'd256 :
                       ramp_alpha;

    assign fade_active = (state != S_IDLE);
    assign fade_busy = busy_ctrl;
    assign opacity = alpha_now;
    assign phase = state;

    wire [16:0] red_product = rgb_in[23:16] * alpha_now;
    wire [16:0] green_product = rgb_in[15:8] * alpha_now;
    wire [16:0] blue_product = rgb_in[7:0] * alpha_now;

    // Use 9-bit opacity and 17-bit products to preserve all RGB bits at full light.
    always @* begin
        if (alpha_now == 9'd256) begin
            rgb_out = rgb_in;
        end else begin
            rgb_out[23:16] = red_product[15:8];
            rgb_out[15:8]  = green_product[15:8];
            rgb_out[7:0]   = blue_product[15:8];
        end
    end

    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if (!ctrl_rst_n) begin
            start_toggle <= 1'b0;
            swap_pending_d <= 1'b0;
            busy_ctrl <= 1'b0;
            commit_sync1 <= 1'b0;
            commit_sync2 <= 1'b0;
            commit_seen <= 1'b0;
            done_sync1 <= 1'b0;
            done_sync2 <= 1'b0;
            done_seen <= 1'b0;
            swap_commit <= 1'b0;
        end else begin
            swap_pending_d <= swap_pending;
            commit_sync1 <= commit_toggle;
            commit_sync2 <= commit_sync1;
            done_sync1 <= done_toggle;
            done_sync2 <= done_sync1;
            swap_commit <= 1'b0;

            if (commit_sync2 != commit_seen) begin
                commit_seen <= commit_sync2;
                swap_commit <= 1'b1;
            end
            if (done_sync2 != done_seen) begin
                done_seen <= done_sync2;
                busy_ctrl <= 1'b0;
            end
            if (swap_pending && !swap_pending_d && !busy_ctrl) begin
                start_toggle <= ~start_toggle;
                busy_ctrl <= 1'b1;
            end
        end
    end

    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            state <= S_IDLE;
            ramp <= FADE_FRAMES[CNT_W-1:0];
            commit_toggle <= 1'b0;
            done_toggle <= 1'b0;
            hold_frames <= 8'd0;
            ack_seen <= 1'b0;
            start_sync1 <= 1'b0;
            start_sync2 <= 1'b0;
            start_seen <= 1'b0;
            start_waiting <= 1'b0;
        end else begin
            start_sync1 <= start_toggle;
            start_sync2 <= start_sync1;

            if (start_sync2 != start_seen) begin
                start_seen <= start_sync2;
                start_waiting <= 1'b1;
            end
            if (start_waiting && frame_start) begin
                start_waiting <= 1'b0;
                if (player_active) begin
                    state <= S_OUT;
                    ramp <= FADE_FRAMES[CNT_W-1:0];
                    hold_frames <= 8'd0;
                    ack_seen <= swap_ack;
                end else begin
                    // Acknowledge without waiting if there is no active raster.
                    done_toggle <= ~done_toggle;
                end
            end else begin
                case (state)
                    S_IDLE: begin
                        ramp <= FADE_FRAMES[CNT_W-1:0];
                    end
                    S_OUT: begin
                        if (frame_start) begin
                            if (ramp == 0) begin
                                state <= S_HOLD;
                                hold_frames <= 8'd0;
                                commit_toggle <= ~commit_toggle;
                            end else begin
                                ramp <= ramp - 1'b1;
                            end
                        end
                    end
                    S_HOLD: begin
                        if (frame_start && swap_ack != ack_seen) begin
                            ack_seen <= swap_ack;
                            state <= S_IN;
                            ramp <= {CNT_W{1'b0}};
                            hold_frames <= 8'd0;
                        end else if (frame_start) begin
                            if (hold_frames >= HOLD_TIMEOUT_FRAMES) begin
                                // Leave black-out if the reader fails to acknowledge.
                                state <= S_IN;
                                ramp <= {CNT_W{1'b0}};
                                hold_frames <= 8'd0;
                            end else begin
                                hold_frames <= hold_frames + 1'b1;
                            end
                        end
                    end
                    S_IN: begin
                        if (frame_start) begin
                            if (ramp >= FADE_FRAMES - 1) begin
                                state <= S_IDLE;
                                done_toggle <= ~done_toggle;
                            end else begin
                                ramp <= ramp + 1'b1;
                            end
                        end
                    end
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule

