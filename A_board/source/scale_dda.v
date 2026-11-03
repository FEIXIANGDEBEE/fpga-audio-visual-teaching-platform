`timescale 1ns/1ps
// Incremental nearest-neighbour source index: floor(dst*SRC/DEST).
// For each destination step, add s to rem and q to idx; a carry adds one
// more to idx and subtracts DEST from rem. q=SRC/DEST, s=SRC-q*DEST.
// rem,s < DEST, so rem+s < 2*DEST and fits REM_W+1 bits.
// The step uses one adder and one subtractor per axis.
module scale_dda #(
    parameter integer DEST  = 640,   // modulus: dest width (640) or dest height (480)
    parameter integer REM_W = 10,    // must satisfy (1 << REM_W) > DEST
    parameter integer Q_W   = 2,     // width of the integer step q
    parameter integer IDX_W = 11     // width of the source index
)(
    input  [REM_W-1:0] rem,          // current remainder, < DEST
    input  [REM_W-1:0] s,            // addend, < DEST
    input  [Q_W-1:0]   q,            // integer step
    input  [IDX_W-1:0] idx,          // current source index
    output [REM_W-1:0] rem_n,        // next remainder
    output [IDX_W-1:0] idx_n,        // next source index
    output             carry         // 1 => the integer step is q+1 this time
);

wire [REM_W:0] sum  = {1'b0, rem} + {1'b0, s};   // < 2*DEST, always positive
wire [REM_W:0] diff = sum - DEST[REM_W:0];       // borrow shows in the MSB

assign carry = ~diff[REM_W];                                        // no borrow
assign rem_n = carry ? diff[REM_W-1:0] : sum[REM_W-1:0];
assign idx_n = idx + {{(IDX_W-Q_W){1'b0}}, q} + {{(IDX_W-1){1'b0}}, carry};

endmodule
