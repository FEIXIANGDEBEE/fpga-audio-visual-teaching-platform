`timescale 1ns/1ps
module reset_sync(input wire clk, input wire arst_n, output wire reset_n);
    (* ASYNC_REG="TRUE" *) reg [2:0] release_pipe;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) release_pipe <= 0;
        else release_pipe <= {release_pipe[1:0],1'b1};
    assign reset_n = release_pipe[2];
endmodule
