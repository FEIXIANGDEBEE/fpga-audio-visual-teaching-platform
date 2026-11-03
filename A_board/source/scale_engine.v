`timescale 1ns/1ps
// Load-time nearest-neighbour scaling into DEST_W x DEST_H pixels.
// Fill and emit share two row banks; row IDs versus need_sy determine reuse.
// A completed frame must contain all destination pixels and drain its source.
// Nonelastic input reserves space for an in-flight 512-byte sector; its row
// watchdog reuses a held row or black and increments fallback_count. Elastic
// input waits for the exact row, with bounded timeouts owned by its caller.
// Image acceptance requires zero fallback/dropped bytes and all source rows.
module scale_engine_v2 #(
    parameter integer ASPECT_FIT = 0,
    parameter integer ELASTIC_INPUT = 0,       // caller retains bounded timeouts
    parameter integer DEST_W     = 640,
    parameter integer DEST_H     = 480,
    parameter integer FIFO_AW    = 12,          // 4096-byte byte FIFO
    parameter integer LINE_AW    = 11,          // 2048-pixel line buffer
    parameter integer WD_MAX     = 1000000      // ~10 ms @ 100 MHz
)(
    input               clk,
    input               rst,

    input               start,
    input  [15:0]       src_w,
    input  [15:0]       src_h,

    input               in_valid,
    input  [7:0]        in_data,
    output              in_ready,
    output              pause,          // 1 => do not start another SD sector
    input               file_eof,       // no more payload bytes will arrive

    output              out_valid,
    output [23:0]       out_data,
    input               out_ready,

    output              busy,
    output              frame_done,
    output [18:0]       dest_cnt_o,

    // Diagnostics used by the TF ingest probe. A successful image must have
    // fallback_count=0, filled_rows=src_h and dropped_bytes=0.
    output reg [31:0]   fallback_count,
    output reg [31:0]   filled_rows,
    output reg [31:0]   dropped_bytes,
    output [37:0] actual_fit
);

localparam integer DEST_N = DEST_W * DEST_H;      // 307200
localparam integer FIFO_N = 1 << FIFO_AW;

// For sector input, pause at 3072: 3072+512=3584 fits the 4096-byte FIFO.
// Elastic input stops at !in_ready each cycle; scale its diagnostic hysteresis
// with FIFO depth. Nonelastic thresholds remain 3072/1024.
localparam [FIFO_AW:0] TH_PAUSE  = ELASTIC_INPUT ? FIFO_N-(FIFO_N>>2) : 3072;
localparam [FIFO_AW:0] TH_RESUME = ELASTIC_INPUT ? (FIFO_N>>2) : 1024;

localparam [2:0] S_WAIT  = 3'd0,
                 S_ROW   = 3'd1,
                 S_DRAIN = 3'd2,
                 S_DONE  = 3'd3,
                 S_FLUSH = 3'd4,
                 S_GEOM  = 3'd5;

// byte FIFO (BRAM, FIFO_N x 8)
(* ram_style = "bram" *) reg [7:0] bfifo [0:FIFO_N-1];
reg [FIFO_AW:0] bf_wp, bf_rp;      // The extra pointer bit distinguishes full from empty.
 // Buffer the short FF-to-EMB address path without changing its address or latency.
wire [FIFO_AW-1:0] bf_rp_dly; /* fehdl keep="true" */
genvar ai;
generate for (ai=0; ai<FIFO_AW; ai=ai+1) begin : g_bfrp_delay
    // TD packing uses EQN and functional simulation uses INIT; both encode identity.
    AL_MAP_LUT1 #(.EQN("(A)"), .INIT(2'b10)) u_buf (.a(bf_rp[ai]), .o(bf_rp_dly[ai]));
end endgenerate
// Protect the write-address hold path with the same zero-cycle buffer.
wire [FIFO_AW-1:0] bf_wp_dly; /* fehdl keep="true" */
genvar wi;
generate for(wi=0;wi<FIFO_AW;wi=wi+1)begin:g_bfwp_delay
    AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(bf_wp[wi]),.o(bf_wp_dly[wi]));
end endgenerate
reg [7:0]       bd;                // 1-deep output latch
reg             bd_v;

wire [FIFO_AW:0] bf_cnt   = bf_wp - bf_rp;
wire             bf_empty = (bf_cnt == {(FIFO_AW+1){1'b0}});
wire             bf_full  = bf_cnt[FIFO_AW];                       // == FIFO_N
wire [FIFO_AW:0] bf_occ   = bf_cnt + {{(FIFO_AW){1'b0}}, bd_v};

wire bf_push = in_valid && !bf_full && !rst && !start;

// latched frame geometry
reg [12:0] pxb_r;                  // 3 * src_w, bytes of real pixel data / row
reg [12:0] rwb_r;                  // 4-aligned row stride
reg [11:0] sw_r, sh_r;             // src_w / src_h (<= 2048)
reg [10:0] qx_r; reg [9:0] sxr_r;
reg [10:0] qy_r; reg [8:0] syr_r;
reg [9:0] fw_r, left_r;
reg [9:0] right_r; // frame geometry, same capture edge as left/width
reg [8:0] fh_r, bottom_r;
assign actual_fit={fw_r,fh_r,left_r,bottom_r};
wire geom_ready, geom_busy, geom_invalid;
wire [9:0] geom_fw, geom_left, geom_rx;
wire [8:0] geom_fh, geom_bottom, geom_ry;
wire [10:0] geom_qx, geom_qy;
generate if (ASPECT_FIT) begin : g_fit
    fit_geometry geometry (
        .clk(clk), .rst(rst), .start(start), .src_w(src_w), .src_h(src_h),
        .busy(geom_busy), .ready(geom_ready), .invalid(geom_invalid),
        .fit_w(geom_fw), .fit_h(geom_fh), .left(geom_left), .bottom(geom_bottom),
        .qx(geom_qx), .qy(geom_qy), .rx(geom_rx), .ry(geom_ry)
    );
end else begin : g_stretch
    assign geom_ready=0; assign geom_busy=0; assign geom_invalid=0;
    assign geom_fw=0; assign geom_fh=0; assign geom_left=0; assign geom_bottom=0;
    assign geom_qx=0; assign geom_qy=0; assign geom_rx=0; assign geom_ry=0;
end endgenerate

wire [12:0] pxb_w = {1'b0, src_w[11:0]} + {src_w[11:0], 1'b0};
wire [12:0] rwb_w = (pxb_w + 13'd3) & ~13'd3;

wire [1:0]  qx_w = (src_w >= 16'd1920) ? 2'd3 :
                   (src_w >= 16'd1280) ? 2'd2 :
                   (src_w >= 16'd640 ) ? 2'd1 : 2'd0;
wire [15:0] qx640 = ({14'd0, qx_w} << 9) + ({14'd0, qx_w} << 7);

wire [2:0]  qy_w = (src_h >= 16'd1920) ? 3'd4 :
                   (src_h >= 16'd1440) ? 3'd3 :
                   (src_h >= 16'd960 ) ? 3'd2 :
                   (src_h >= 16'd480 ) ? 3'd1 : 3'd0;
wire [15:0] qy480 = ({13'd0, qy_w} << 8) + ({13'd0, qy_w} << 7)
                  + ({13'd0, qy_w} << 6) + ({13'd0, qy_w} << 5);

wire [15:0] sxr_w = src_w - qx640;      // < 640
wire [15:0] syr_w = src_h - qy480;      // < 480

// line-buffer bank bookkeeping (L1 instance below)
reg         bv0, bv1;               // bank holds a valid source row
reg [10:0]  br0, br1;               // which source row it holds

// fill side (byte stream -> one source row -> a free bank)
reg [11:0] f_sy;                    // source row being consumed
reg [12:0] f_pos;                   // byte index inside the row
reg [1:0]  f_ph;                    // B/G/R phase
reg [10:0] f_x;                     // source column being written
reg        f_act;                   // a row fill is in progress
reg        f_sel;                   // bank being filled
reg        fill_arm;
reg        eof_r;
reg [7:0]  pb0, pb1;
wire [7:0] pb1_dly; /* fehdl keep="true" */
genvar di;
generate for (di=0; di<8; di=di+1) begin : g_pb1_delay
    AL_MAP_LUT1 #(.EQN("(A)"), .INIT(2'b10)) u_buf (.a(pb1[di]), .o(pb1_dly[di]));
end endgenerate

// emit side (bank -> 640-wide destination row)
reg [2:0]  em_st;
reg [9:0]  dest_x;
reg [8:0]  dest_y;
reg [18:0] dest_cnt;
reg [10:0] col;                     // source column for the next dest pixel
reg [9:0]  xR;                      // X remainder
reg [8:0]  yR;                      // Y remainder
reg [10:0] need_sy;                 // source row the current dest row needs
reg        e_sel;                   // bank being read
reg        blk_row;                 // watchdog: this row is padding (black)
reg        pad_row;                 // normal border, never watchdog fallback
reg        tail_flush;              // release source tail after final fit row
reg        blk_d;                   // blk_row delayed one clk (= BRAM latency)
reg [19:0] wd_cnt;
reg        rd_v;                    // stage-1 valid (linebuf data available)
reg        out_v;                   // stage-2 valid (out_d holds a pixel)
reg [23:0] out_d;
reg        frame_done_r;

// SD pacing
reg sd_stall;

// L0: two DDA step units (X and Y)
wire [10:0] xt = {1'b0,xR}+{1'b0,sxr_r};
wire [9:0] yt = {1'b0,yR}+{1'b0,syr_r};
// Carry and difference from the same unsigned subtractor, no new stage.
wire [11:0] x_delta = {1'b0,xt}-{2'b0,fw_r};
wire [10:0] y_delta = {1'b0,yt}-{2'b0,fh_r};
wire cx = !x_delta[11];
wire cy = !y_delta[10];
wire [10:0] xr_full = cx ? x_delta[10:0] : xt;
wire [9:0] yr_full = cy ? y_delta[9:0] : yt;
wire [9:0] xr_n = xr_full[9:0];
wire [8:0] yr_n = yr_full[8:0];
wire [11:0] col_full = {1'b0,col}+{1'b0,qx_r}+{11'd0,cx};
wire [11:0] nsy_full = {1'b0,need_sy}+{1'b0,qy_r}+{11'd0,cy};
wire [10:0] col_n = col_full[10:0];
wire [10:0] nsy_n = nsy_full[10:0];
wire active_x = dest_x>=left_r && dest_x<right_r;
wire active_y = dest_y>=bottom_r && dest_y<(bottom_r+fh_r);
wire pixel_black = blk_row || pad_row || !active_x;

// combinational control
wire        s2_ok   = !out_v || out_ready;
wire        s2_load = rd_v && s2_ok;
wire        em_req  = (em_st == S_ROW);
wire        s1_load = em_req && (!rd_v || s2_load);

// Reuse an empty bank or a row older than need_sy. Once rendering finishes,
// flush the remaining source rows.
wire        flush_mode = (em_st == S_FLUSH) || tail_flush;
wire        free0  = !bv0 || (br0 < need_sy) || flush_mode;
wire        free1  = !bv1 || (br1 < need_sy) || flush_mode;
wire        row_begin = !f_act && fill_arm && (f_sy < sh_r) &&
                        (free0 || free1) && bd_v;
wire        f_consume = bd_v && (f_act || row_begin);
wire        row_end   = f_consume && ((f_pos + 13'd1) >= rwb_r);

// pop_issue must remain independent of bd_v. If FIFO reads waited for
// f_consume, an empty byte latch could never fill. Fetch while a fill is
// active or another row may begin, then consume through the one-byte latch.
wire        want_row  = fill_arm && (f_sy < sh_r) && (free0 || free1);
wire        pop_issue = (f_act || (!f_act && (want_row || flush_mode))) && !bf_empty;

wire        line_we    = f_consume && (f_pos < pxb_r) && (f_ph == 2'd2);
wire [23:0] line_wdata = {bd, pb1_dly, pb0};    // BMP stores B,G,R -> {R,G,B}

// prefer an empty bank; otherwise recycle the older (lower row id) one
wire        sel_pref = !bv0 ? 1'b0 :
                       (!bv1 ? 1'b1 : ((br0 <= br1) ? 1'b0 : 1'b1));

wire        hit0 = bv0 && (br0 == need_sy);
wire        hit1 = bv1 && (br1 == need_sy);
wire        hit  = hit0 || hit1;

// Declare the line-buffer connections before instantiation to avoid implicit one-bit nets.
wire [LINE_AW-1:0] lb_wa = f_x[LINE_AW-1:0];
wire [LINE_AW-1:0] lb_ra = col[LINE_AW-1:0];
wire [23:0]        lb_rd;

scale_linebuf #(.AW(LINE_AW), .DW(24)) u_linebuf (
    .clk(clk),
    .wr_en(line_we), .wr_sel(f_sel), .wr_addr(lb_wa), .wr_data(line_wdata),
    .rd_en(s1_load & ~pixel_black), .rd_sel(e_sel), .rd_addr(lb_ra),
    .rd_data(lb_rd)
);

wire        starved = eof_r && bf_empty && !bd_v;
wire        src_drained = !fill_arm && !f_act && bf_empty && !bd_v;
wire        flush_consume = flush_mode && bd_v;

assign in_ready   = !bf_full;
assign pause      = sd_stall;
assign out_valid  = out_v;
assign out_data   = out_d;
assign frame_done = frame_done_r;
assign dest_cnt_o = dest_cnt;

assign busy = !frame_done_r &&
              (fill_arm || f_act || bv0 || bv1 ||
               !bf_empty || bd_v || out_v || rd_v || (em_st != S_DONE));

// memories
always @(posedge clk) begin
    if (bf_push) bfifo[bf_wp_dly] <= in_data;
end

// Hold bd when pop_issue is low so a stalled fill keeps its byte.
// This block is its sole driver.
always @(posedge clk) begin
    if (pop_issue) bd <= bfifo[bf_rp_dly];
end

// SD pacing
always @(posedge clk or posedge rst) begin
    if (rst || start)              sd_stall <= 1'b0;
    else if (bf_occ >= TH_PAUSE)   sd_stall <= 1'b1;
    else if (bf_occ <= TH_RESUME)  sd_stall <= 1'b0;
end

// main sequential logic
always @(posedge clk or posedge rst) begin
    if (rst) begin
        bf_wp <= 0; bf_rp <= 0; bd_v <= 1'b0;

        pxb_r <= 13'd0; rwb_r <= 13'd0; sw_r <= 12'd0; sh_r <= 12'd0;
        qx_r  <= 2'd0;  sxr_r <= 10'd0; qy_r <= 3'd0;  syr_r <= 9'd0;
        fw_r<=640; fh_r<=480; left_r<=0; bottom_r<=0; right_r<=640;
        pad_row<=0; tail_flush<=0;

        bv0 <= 1'b0; bv1 <= 1'b0; br0 <= 11'd0; br1 <= 11'd0;

        f_sy <= 12'd0; f_pos <= 13'd0; f_ph <= 2'd0; f_x <= 11'd0;
        f_act <= 1'b0; f_sel <= 1'b0; fill_arm <= 1'b0;
        eof_r <= 1'b0; pb0 <= 8'd0; pb1 <= 8'd0;

        // Remain idle until start: card scanning may outlast the row watchdog.
        em_st <= S_DONE; dest_x <= 10'd0; dest_y <= 9'd0; dest_cnt <= 19'd0;
        col <= 11'd0; xR <= 10'd0; yR <= 9'd0; need_sy <= 11'd0;
        e_sel <= 1'b0; blk_row <= 1'b0; wd_cnt <= 20'd0;
        rd_v <= 1'b0; out_v <= 1'b0; out_d <= 24'd0; frame_done_r <= 1'b0;
        blk_d <= 1'b0;
        fallback_count <= 32'd0; filled_rows <= 32'd0; dropped_bytes <= 32'd0;
    end else if (start) begin
        bf_wp <= 0; bf_rp <= 0; bd_v <= 1'b0;

        pxb_r <= pxb_w; rwb_r <= rwb_w;
        sw_r  <= src_w[11:0]; sh_r <= src_h[11:0];
        qx_r  <= qx_w;  sxr_r <= sxr_w[9:0];
        qy_r  <= qy_w;  syr_r <= syr_w[8:0];
        fw_r<=640; fh_r<=480; left_r<=0; bottom_r<=0; right_r<=640;
        pad_row<=0; tail_flush<=0;

        bv0 <= 1'b0; bv1 <= 1'b0; br0 <= 11'd0; br1 <= 11'd0;

        f_sy <= 12'd0; f_pos <= 13'd0; f_ph <= 2'd0; f_x <= 11'd0;
        f_act <= 1'b0; f_sel <= 1'b0; fill_arm <= 1'b1;
        eof_r <= 1'b0;

        em_st <= ASPECT_FIT ? S_GEOM : S_WAIT; dest_x <= 10'd0; dest_y <= 9'd0; dest_cnt <= 19'd0;
        col <= 11'd0; xR <= 10'd0; yR <= 9'd0; need_sy <= 11'd0;
        e_sel <= 1'b0; blk_row <= 1'b0; wd_cnt <= 20'd0;
        rd_v <= 1'b0; out_v <= 1'b0; frame_done_r <= 1'b0;
        blk_d <= 1'b0;
        fallback_count <= 32'd0; filled_rows <= 32'd0; dropped_bytes <= 32'd0;
    end else begin
        // Keep stage-one metadata with its pixel token through stalls.
        if (s1_load) blk_d <= pixel_black;

        if (in_valid && !in_ready)
            dropped_bytes <= dropped_bytes + 32'd1;

        // --------- byte latch ----------
        if (bf_push)
            bf_wp <= bf_wp + 1'b1;

        if (pop_issue) begin
            bf_rp <= bf_rp + 1'b1;
            bd_v  <= 1'b1;
        end else if (f_consume || flush_consume) begin
            bd_v  <= 1'b0;
        end

        // Invalidate the target bank when filling starts; emit must not read a
        // partly overwritten row.
        if (row_begin) begin
            f_act <= 1'b1;
            f_sel <= sel_pref;
            if (sel_pref) bv1 <= 1'b0;
            else          bv0 <= 1'b0;
        end

        if (f_consume) begin
            if (f_pos < pxb_r) begin
                case (f_ph)
                    2'd0: begin pb0 <= bd; f_ph <= 2'd1; end
                    2'd1: begin pb1 <= bd; f_ph <= 2'd2; end
                    default: begin f_ph <= 2'd0; f_x <= f_x + 11'd1; end
                endcase
            end

            if (row_end) begin
                f_pos <= 13'd0; f_ph <= 2'd0; f_x <= 11'd0;
                f_act <= 1'b0;
                if (f_sel) begin bv1 <= 1'b1; br1 <= f_sy[10:0]; end
                else       begin bv0 <= 1'b1; br0 <= f_sy[10:0]; end
                f_sy <= f_sy + 12'd1;
                filled_rows <= filled_rows + 32'd1;
                if ((f_sy + 12'd1) >= sh_r)
                    fill_arm <= 1'b0;
            end else begin
                f_pos <= f_pos + 13'd1;
            end
        end

        // --------- truncation guard: source ran dry ----------
        if (file_eof)
            eof_r <= 1'b1;
        if (starved && fill_arm) begin
            fill_arm <= 1'b0;
            if (f_act) begin
                f_act <= 1'b0; f_pos <= 13'd0; f_ph <= 2'd0; f_x <= 11'd0;
            end
        end

        // --------- emit: 2-stage elastic pipe ----------
        rd_v <= s1_load | (rd_v & ~s2_load);
        if (s2_load) begin
            out_d <= blk_d ? 24'h000000 : lb_rd;
            out_v <= 1'b1;
        end else if (out_ready) begin
            out_v <= 1'b0;
        end

        if (out_v && out_ready)
            dest_cnt <= dest_cnt + 19'd1;

        case (em_st)
            S_GEOM: begin
                if (geom_ready) begin
                    fw_r<=geom_fw; fh_r<=geom_fh; left_r<=geom_left; bottom_r<=geom_bottom; right_r<=geom_left+geom_fw;
                    qx_r<=geom_qx; qy_r<=geom_qy; sxr_r<=geom_rx; syr_r<=geom_ry;
                    wd_cnt<=0; em_st<=S_WAIT;
                end
            end
            S_WAIT: begin
                if (!active_y) begin
                    pad_row<=1; blk_row<=0; dest_x<=0; col<=0; xR<=0;
                    wd_cnt<=0; em_st<=S_ROW;
                end else if (hit) begin
                    pad_row <= 1'b0;
                    e_sel   <= hit0 ? 1'b0 : 1'b1;
                    blk_row <= 1'b0;
                    dest_x  <= 10'd0;
                    col     <= 11'd0;
                    xR      <= 10'd0;
                    wd_cnt  <= 20'd0;
                    em_st   <= S_ROW;
                end else if (!ELASTIC_INPUT && wd_cnt >= WD_MAX[19:0]) begin
                    pad_row <= 1'b0;
                    // For nonelastic input, reuse a held row on watchdog expiry or emit black.
                    fallback_count <= fallback_count + 32'd1;
                    wd_cnt  <= 20'd0;
                    e_sel   <= bv0 ? 1'b0 : 1'b1;
                    blk_row <= !(bv0 || bv1);
                    dest_x  <= 10'd0;
                    col     <= 11'd0;
                    xR      <= 10'd0;
                    em_st   <= S_ROW;
                end else begin
                    // Elastic input may pause. Wait for the exact row; the enclosing loader
                    // rejects timeout or incomplete-frame failures without publishing fallback.
                    wd_cnt <= ELASTIC_INPUT ? 20'd0 : wd_cnt + 20'd1;
                end
            end

            S_ROW: begin
                if (s1_load) begin
                    if (dest_x == DEST_W[9:0] - 10'd1)
                        em_st <= S_DRAIN;
                    else
                        dest_x <= dest_x + 10'd1;
                    if (!pad_row && active_x) begin
                        xR <= xr_n;
                        col <= col_n;
                    end
                end
            end

            S_DRAIN: begin
                if (!rd_v && !out_v) begin
                    if (ASPECT_FIT && active_y && dest_y==(bottom_r+fh_r-1'b1))
                        tail_flush<=1;
                    if (dest_y == DEST_H[8:0] - 9'd1) begin
                        // Drain trailing source rows after output completes, before frame_done,
                        // so the BMP loader consumes the entire payload.
                        em_st <= S_FLUSH;
                    end else begin
                        if (active_y) begin
                            yR <= yr_n;
                            need_sy <= nsy_n;
                        end
                        dest_y  <= dest_y + 9'd1;
                        wd_cnt  <= 20'd0;
                        em_st   <= S_WAIT;
                    end
                end
            end

            S_FLUSH: begin
                if (src_drained) begin
                    frame_done_r <= 1'b1;
                    em_st        <= S_DONE;
                end
            end

            default: em_st <= S_DONE;
        endcase
    end
end

endmodule
