`timescale 1ns/1ps
// SHOW_AHEAD exposes the current pixel before pop. The Anlogic core owns
// Gray-pointer CDC, BRAM and reset/flag timing for this prefetch FIFO.
module video_fifo #(
    parameter AW = 9
) (
    input wire wclk, wrst_n, wflush, push,
    input wire [31:0] wdata,
    output wire full,
    output wire [AW:0] wcount,
    input wire rclk, rrst_n, rflush, pop,
    output wire [31:0] rdata,
    output wire empty,
    output wire [AW:0] rcount
);
    // Combine both frame-side flush requests into the shared asynchronous
    // reset so neither pointer retains an old frame.
    wire fifo_rst = !wrst_n || !rrst_n || wflush || rflush;
    wire [31:0] fifo_dout;
    wire [AW-1:0] wrusedw, rdusedw;
    wire fifo_valid;

    rfifo_32_32_512 #(
        .DATA_WIDTH_W(32), .DATA_WIDTH_R(32),
        .ADDR_WIDTH_W(AW), .ADDR_WIDTH_R(AW),
        .AL_FULL_NUM((1<<AW)-4), .AL_EMPTY_NUM(1),
        .SHOW_AHEAD_EN(1'b1), .OUTREG_EN("NOREG")
    ) fifo_core (
        .rst(fifo_rst), .clkw(wclk), .clkr(rclk),
        .we(push), .di(wdata), .re(pop), .dout(fifo_dout),
        .valid(fifo_valid), .full_flag(full), .empty_flag(empty),
        .afull(), .aempty(), .wrusedw(wrusedw), .rdusedw(rdusedw)
    );

    assign rdata = fifo_dout;
    // Zero-extend the generated 512-word FIFO's nine-bit counts to the
    // wrapper's AW+1 count width.
    assign wcount = wrusedw;
    assign rcount = rdusedw;
endmodule
