`timescale 1ns/1ps
// Share 2M x 32 SDRAM between two independent 10 MHz link-clock clients.
// The physical interface uses aligned four-beat requests.
module media_memory #(parameter STARTUP_CYCLES=2000000, parameter VIDEO_WORDS=307200) (
    input wire sys_clk, sys_rst_n,
    input wire c0_clk, c0_req_valid, c0_req_write,
    input wire [20:0] c0_req_addr,
    input wire [31:0] c0_req_data,
    input wire [3:0] c0_req_dm,
    output wire c0_req_ready, c0_rsp_valid,
    output wire [31:0] c0_rsp_data,
    output wire c0_rsp_error,
    input wire c0_rsp_ready,
    input wire c1_clk, c1_req_valid, c1_req_write,
    input wire [20:0] c1_req_addr,
    input wire [31:0] c1_req_data,
    input wire [3:0] c1_req_dm,
    output wire c1_req_ready, c1_rsp_valid,
    output wire [31:0] c1_rsp_data,
    output wire c1_rsp_error,
    input wire c1_rsp_ready,
    output wire video_clk, video_reset_n,
    input wire video_req,
    input wire [20:0] video_addr,
    output wire video_req_ready, video_valid,
    output wire [31:0] video_data,
    output wire video_done, video_error,
    output wire memory_ready,
    output reg [31:0] service_count,
    output reg [31:0] service_errors,
    input wire [31:0] probe_stream_data,
    input wire [20:0] probe_stream_addr,
    input wire probe_stream_valid,
    input wire layer_mode,layer_req,input wire [20:0] layer_addr,
    output wire layer_req_ready,layer_valid,output wire [31:0] layer_data,
    output wire layer_done,layer_error
);
    wire clk_aux, clk, clk_sft, locked;
    sys_pll pll(.refclk(sys_clk), .reset(1'b0), .extlock(locked),
                .clk0_out(clk_aux), .clk1_out(clk), .clk2_out(clk_sft));
    wire reset_n = sys_rst_n && locked;
    reg [20:0] reset_count = 0;
    reg rst = 1;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin reset_count <= 0; rst <= 1; end
        else if (reset_count < STARTUP_CYCLES) begin
            reset_count <= reset_count + 1'b1;
            rst <= 1;
        end else rst <= 0;
    end

    wire init, refresh, mem_busy, mem_rd_valid;
    wire [31:0] mem_rd_data;
    wire app_busy, app_rd_valid;
    wire [31:0] app_rd_data;
    wire app_wr_en, app_rd_en;
    wire [20:0] app_wr_addr, app_rd_addr;
    wire [31:0] app_wr_data;
    wire [3:0] app_wr_dm;
    wire mem_wr_en, mem_rd_en;
    wire [20:0] mem_wr_addr, mem_rd_addr;
    wire [31:0] mem_wr_data;
    wire [3:0] mem_wr_dm;
    assign memory_ready = init && !rst;
    assign video_clk=clk;
    assign video_reset_n=!rst;
    wire burst_busy,burst_rd_en,burst_done,burst_error;
    wire [20:0] burst_addr;
    wire burst_start=(video_req && video_req_ready)||(layer_req && layer_req_ready);
    reg layer_owner;
    always @(posedge clk or posedge rst)if(rst)layer_owner<=0;else if(burst_start)layer_owner<=!(video_req && video_req_ready);
    wire raw_valid;wire [31:0] raw_data;
    assign video_done=burst_done && !layer_owner;
    assign video_error=burst_error && !layer_owner;
    assign video_valid=raw_valid && !layer_owner;assign video_data=raw_data;
    assign layer_done=burst_done && layer_owner;assign layer_error=burst_error && layer_owner;
    assign layer_valid=raw_valid && layer_owner;assign layer_data=raw_data;
    // Reserve two 307200-word working frames and four resident scene-cache slots.
    sdram_read_burst #(.BASE(0),.WORDS(1843200)) video_burst(
        .clk(clk),.rst(rst),.start(burst_start),.address(video_req && video_req_ready ? video_addr:layer_addr),
        .mem_busy(mem_busy),.refresh(refresh),.rd_valid(mem_rd_valid),
        .rd_data(mem_rd_data),.busy(burst_busy),.rd_en(burst_rd_en),.rd_addr(burst_addr),
        .data_valid(raw_valid),.data(raw_data),.done(burst_done),.error(burst_error));
    wire physical_rd_en=burst_busy ? burst_rd_en : mem_rd_en;
    wire [20:0] physical_rd_addr=burst_busy ? burst_addr : mem_rd_addr;
    sdram memory(.Clk(clk), .Clk_sft(clk_sft), .Rst(rst),
        .Sdr_init_done(init), .Sdr_init_ref_vld(refresh), .Sdr_busy(mem_busy),
        .App_wr_en(mem_wr_en), .App_wr_addr(mem_wr_addr), .App_wr_dm(mem_wr_dm),
        .App_wr_din(mem_wr_data), .App_rd_en(physical_rd_en), .App_rd_addr(physical_rd_addr),
        .Sdr_rd_en(mem_rd_valid), .Sdr_rd_dout(mem_rd_data));
    sdram_word_adapter #(.READ_DATA_DELAY(1)) adapter(
        .clk(clk), .rst(rst), .mem_init_done(init), .mem_refresh(refresh),
        .mem_busy(mem_busy), .wr_en(app_wr_en), .wr_addr(app_wr_addr),
        .wr_dm(app_wr_dm), .wr_data(app_wr_data), .rd_en(app_rd_en),
        .rd_addr(app_rd_addr), .busy(app_busy), .rd_valid(app_rd_valid),
        .rd_data(app_rd_data), .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr),
        .mem_wr_dm(mem_wr_dm), .mem_wr_data(mem_wr_data),
        .mem_rd_en(mem_rd_en), .mem_rd_addr(mem_rd_addr),
        .mem_rd_valid(mem_rd_valid && !burst_busy), .mem_rd_data(mem_rd_data));

    wire req0_toggle, req1_toggle;
    wire req0_write, req1_write;
    wire [20:0] req0_addr, req1_addr;
    wire [31:0] req0_data, req1_data;
    wire [3:0] req0_dm, req1_dm;
    reg rsp0_toggle, rsp1_toggle, rsp0_error, rsp1_error;
    reg [31:0] rsp0_data, rsp1_data;
    mem_client client0(
        .clk(c0_clk), .reset_n(reset_n), .req_valid(c0_req_valid),
        .req_write(c0_req_write), .req_addr(c0_req_addr), .req_data(c0_req_data),
        .req_dm(c0_req_dm), .req_ready(c0_req_ready), .rsp_valid(c0_rsp_valid),
        .rsp_data(c0_rsp_data), .rsp_error(c0_rsp_error), .rsp_ready(c0_rsp_ready),
        .m_req_toggle(req0_toggle), .m_req_write(req0_write),
        .m_req_addr(req0_addr), .m_req_data(req0_data), .m_req_dm(req0_dm),
        .m_rsp_toggle(rsp0_toggle), .m_rsp_data(rsp0_data), .m_rsp_error(rsp0_error));
    mem_client client1(
        .clk(c1_clk), .reset_n(reset_n), .req_valid(c1_req_valid),
        .req_write(c1_req_write), .req_addr(c1_req_addr), .req_data(c1_req_data),
        .req_dm(c1_req_dm), .req_ready(c1_req_ready), .rsp_valid(c1_rsp_valid),
        .rsp_data(c1_rsp_data), .rsp_error(c1_rsp_error), .rsp_ready(c1_rsp_ready),
        .m_req_toggle(req1_toggle), .m_req_write(req1_write),
        .m_req_addr(req1_addr), .m_req_data(req1_data), .m_req_dm(req1_dm),
        .m_rsp_toggle(rsp1_toggle), .m_rsp_data(rsp1_data), .m_rsp_error(rsp1_error));

    (* ASYNC_REG="TRUE" *) reg req0_s1, req0_s2, req1_s1, req1_s2;
    reg req0_seen, req1_seen, prefer1, selected;
    reg [2:0] state;
    localparam IDLE=0, ISSUE=1, WAIT_WRITE=2, WAIT_READ=3, RESPOND=4, VIDEO=5;
    reg req_write_r;
    reg [20:0] req_addr_r;
    reg [31:0] req_data_r, result_r;
    reg [3:0] req_dm_r;
    reg error_r, saw_busy;
    reg [20:0] probe_saved_addr;reg probe_saved_valid;
    reg [15:0] timeout_count;
    wire pending0 = req0_s2 != req0_seen;
    wire pending1 = req1_s2 != req1_seen;
    // Keep ordinary-page priority. For layered frames, serve BASE FIFO first,
    // then a ready auxiliary block, then clients. With low-water 512, a
    // 274-cycle burst leaves at least 375 pixels.
    assign video_req_ready=state==IDLE && memory_ready && !app_busy && (layer_mode || (!pending0 && !pending1));
    assign layer_req_ready=state==IDLE && memory_ready && !app_busy && !video_req;
    assign app_wr_en = (state == ISSUE) && req_write_r && !app_busy;
    // Two read-only diagnostic addresses lie outside the image/work buffers
    // and return through the same acknowledged response bundle.
    wire probe_read=!selected && !req_write_r &&
        (req_addr_r==21'd2097120 || req_addr_r==21'd2097121);
    assign app_rd_en = (state == ISSUE) && !req_write_r && !app_busy && !probe_read;
    assign app_wr_addr = req_addr_r;
    assign app_rd_addr = req_addr_r;
    assign app_wr_data = req_data_r;
    assign app_wr_dm = req_dm_r;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            req0_s1<=0; req0_s2<=0; req1_s1<=0; req1_s2<=0;
            req0_seen<=0; req1_seen<=0; prefer1<=0; selected<=0;
            rsp0_toggle<=0; rsp1_toggle<=0; rsp0_data<=0; rsp1_data<=0;
            rsp0_error<=0; rsp1_error<=0;
            state<=IDLE; req_write_r<=0; req_addr_r<=0; req_data_r<=0;
            req_dm_r<=0; result_r<=0; error_r<=0; saw_busy<=0;
            timeout_count<=0; service_count<=0; service_errors<=0;
            probe_saved_addr<=0;probe_saved_valid<=0;
        end else begin
            req0_s1<=req0_toggle; req0_s2<=req0_s1;
            req1_s1<=req1_toggle; req1_s2<=req1_s1;
            case (state)
                IDLE: begin
                    timeout_count<=0; saw_busy<=0; error_r<=0;
                    if (burst_start) state<=VIDEO;
                    else if (pending0 || pending1) begin
                        selected <= pending1 && (prefer1 || !pending0);
                        if (pending1 && (prefer1 || !pending0)) begin
                            req1_seen <= req1_s2;
                            req_write_r<=req1_write; req_addr_r<=req1_addr;
                            req_data_r<=req1_data; req_dm_r<=req1_dm;
                            prefer1<=0;
                        end else begin
                            req0_seen <= req0_s2;
                            req_write_r<=req0_write; req_addr_r<=req0_addr;
                            req_data_r<=req0_data; req_dm_r<=req0_dm;
                            prefer1<=1;
                        end
                        state<=ISSUE;
                    end
                end
                ISSUE: begin
                    if(probe_read && memory_ready && !app_busy)begin
                        if(req_addr_r==21'd2097120)begin
                            result_r<=probe_stream_data;error_r<=!probe_stream_valid;
                            probe_saved_addr<=probe_stream_addr;probe_saved_valid<=probe_stream_valid;
                        end else begin
                            result_r<={11'd0,probe_saved_addr};error_r<=!probe_saved_valid;
                        end
                        state<=RESPOND;
                    end else if (!memory_ready) begin
                        // Permit the first preload to wait through SDRAM power-up and initialization.
                        timeout_count<=0;
                    end else if (!app_busy) begin
                        state<=req_write_r ? WAIT_WRITE : WAIT_READ;
                        timeout_count<=0;
                    end else if (timeout_count==16'hffff) begin
                        error_r<=1; result_r<=0; state<=RESPOND;
                    end else timeout_count<=timeout_count+1'b1;
                end
                WAIT_WRITE: begin
                    timeout_count<=timeout_count+1'b1;
                    if (app_busy) saw_busy<=1;
                    if (saw_busy && !app_busy) begin
                        result_r<=0; state<=RESPOND;
                    end else if (timeout_count==16'hffff) begin
                        error_r<=1; result_r<=0; state<=RESPOND;
                    end
                end
                WAIT_READ: begin
                    timeout_count<=timeout_count+1'b1;
                    if (app_rd_valid) begin
                        result_r<=app_rd_data; state<=RESPOND;
                    end else if (timeout_count==16'hffff) begin
                        error_r<=1; result_r<=0; state<=RESPOND;
                    end
                end
                RESPOND: begin
                    service_count<=service_count+1'b1;
                    if (error_r) service_errors<=service_errors+1'b1;
                    if (selected) begin
                        rsp1_data<=result_r; rsp1_error<=error_r;
                        rsp1_toggle<=!rsp1_toggle;
                    end else begin
                        rsp0_data<=result_r; rsp0_error<=error_r;
                        rsp0_toggle<=!rsp0_toggle;
                    end
                    state<=IDLE;
                end
                VIDEO: if(burst_done) begin
                    if(burst_error) service_errors<=service_errors+1'b1;
                    state<=IDLE;
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
