`timescale 1ns/1ps
// Adapt single-word requests to APUG011 aligned four-word bursts. The vendor
// core needs a continuous request to issue READ/WRITE. Mask unused write
// beats and select the requested read beat; keep the burst uninterrupted.
module sdram_word_adapter #(parameter READ_DATA_DELAY=0) (
    input wire clk, input wire rst,
    input wire mem_init_done, input wire mem_refresh, input wire mem_busy,
    input wire wr_en, input wire [20:0] wr_addr,
    input wire [3:0] wr_dm, input wire [31:0] wr_data,
    input wire rd_en, input wire [20:0] rd_addr,
    output wire busy, output reg rd_valid, output reg [31:0] rd_data,
    output wire mem_wr_en, output wire [20:0] mem_wr_addr,
    output wire [3:0] mem_wr_dm, output wire [31:0] mem_wr_data,
    output wire mem_rd_en, output wire [20:0] mem_rd_addr,
    input wire mem_rd_valid, input wire [31:0] mem_rd_data
);
    localparam IDLE=3'd0, WRITE=3'd1, READ=3'd2, WAIT_READ=3'd3, DRAIN=3'd4;
    reg [2:0] state;
    reg [20:0] base;
    reg [1:0] selected, beat, received;
    reg [31:0] data_latch, selected_data;
    reg [3:0] dm_latch;
    reg [5:0] wait_count;
    reg [31:0] mem_rd_data_d;
    wire [31:0] aligned_read_data = READ_DATA_DELAY ? mem_rd_data_d : mem_rd_data;
    // The captured 41.667 MHz / 180-degree interface has dout one clock ahead
    // of valid. Register dout every clock, including the clock before valid.
    always @(posedge clk) mem_rd_data_d <= mem_rd_data;
    assign busy = (state != IDLE) || !mem_init_done || mem_refresh || mem_busy;
    assign mem_wr_en = (state == WRITE);
    assign mem_rd_en = (state == READ);
    assign mem_wr_addr = {base[20:2],beat};
    assign mem_rd_addr = {base[20:2],beat};
    assign mem_wr_data = data_latch;
    // The vendor propagates this mask to DQM outside writes too. Keep DQM low
    // on reads so SDRAM can drive the bus.
    assign mem_wr_dm = (state == WRITE) ? ((beat == selected) ? dm_latch : 4'hf) : 4'h0;
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE; base<=0;selected<=0;beat<=0;received<=0;
            data_latch<=0;dm_latch<=4'hf;selected_data<=0;
            wait_count<=0;rd_valid<=0;rd_data<=0;
        end else begin
            rd_valid<=0;
            case(state)
                IDLE: if(!busy) begin
                    beat<=0;received<=0;
                    if(wr_en) begin
                        base<={wr_addr[20:2],2'b00}; selected<=wr_addr[1:0];
                        data_latch<=wr_data;dm_latch<=wr_dm;state<=WRITE;
                    end else if(rd_en) begin
                        base<={rd_addr[20:2],2'b00};selected<=rd_addr[1:0];state<=READ;
                    end
                end
                WRITE: if(beat==2'd3) begin state<=DRAIN;wait_count<=6'd16;end
                       else beat<=beat+1'b1;
                READ: if(beat==2'd3) begin state<=WAIT_READ;wait_count<=0;end
                      else beat<=beat+1'b1;
                WAIT_READ: begin
                    wait_count<=wait_count+1'b1;
                    if(mem_rd_valid) begin
                        if(received==selected) selected_data<=aligned_read_data;
                        if(received==2'd3) begin
                            rd_data<=(selected==2'd3)?aligned_read_data:selected_data;
                            rd_valid<=1;state<=DRAIN;wait_count<=6'd8;
                        end else received<=received+1'b1;
                    end else if(wait_count==6'd47) begin
                        // Leave a missing response to the caller's read watchdog, then drain the adapter.
                        state<=DRAIN;wait_count<=6'd8;
                    end
                end
                DRAIN: if(wait_count!=0) wait_count<=wait_count-1'b1;
                       else if(!mem_busy && !mem_refresh) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
