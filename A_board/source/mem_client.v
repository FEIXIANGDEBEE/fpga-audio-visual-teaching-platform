`timescale 1ns/1ps
// Allow one outstanding request. Hold each request/response bundle until
// the matching toggle has crossed the other domain's two synchronizer stages.
module mem_client (
    input  wire clk, reset_n,
    input  wire req_valid, req_write,
    input  wire [20:0] req_addr,
    input  wire [31:0] req_data,
    input  wire [3:0] req_dm,
    output wire req_ready,
    output reg  rsp_valid,
    output reg  [31:0] rsp_data,
    output reg  rsp_error,
    input  wire rsp_ready,
    output reg  m_req_toggle,
    output reg  m_req_write,
    output reg  [20:0] m_req_addr,
    output reg  [31:0] m_req_data,
    output reg  [3:0] m_req_dm,
    input  wire m_rsp_toggle,
    input  wire [31:0] m_rsp_data,
    input  wire m_rsp_error
);
    reg pending, rsp_seen;
    (* ASYNC_REG="TRUE" *) reg rsp_sync1, rsp_sync2;
    assign req_ready = reset_n && !pending && !rsp_valid;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pending <= 0; rsp_seen <= 0; rsp_sync1 <= 0; rsp_sync2 <= 0;
            m_req_toggle <= 0; m_req_write <= 0; m_req_addr <= 0;
            m_req_data <= 0; m_req_dm <= 0;
            rsp_valid <= 0; rsp_data <= 0; rsp_error <= 0;
        end else begin
            rsp_sync1 <= m_rsp_toggle;
            rsp_sync2 <= rsp_sync1;
            if (rsp_valid && rsp_ready) rsp_valid <= 0;
            if (pending && rsp_sync2 != rsp_seen) begin
                rsp_seen <= rsp_sync2;
                rsp_data <= m_rsp_data;
                rsp_error <= m_rsp_error;
                rsp_valid <= 1;
                pending <= 0;
            end
            if (req_valid && req_ready) begin
                m_req_write <= req_write;
                m_req_addr <= req_addr;
                m_req_data <= req_data;
                m_req_dm <= req_dm;
                m_req_toggle <= !m_req_toggle;
                pending <= 1;
            end
        end
    end
endmodule
