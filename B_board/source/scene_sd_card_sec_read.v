`timescale 1ns/1ps

module scene_sd_card_sec_read
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter  SPI_HIGH_SPEED_DIV = 0           // spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
)
(
	input            clk,
	input            rst,
	output reg [32:0] card_sectors,
	output reg init_error,
	output reg [15:0] block_read_len,
	output reg       sd_init_done,
	input            sd_sec_read,
	input[31:0]      sd_sec_read_addr,
	output[7:0]      sd_sec_read_data,
	output           sd_sec_read_data_valid,
	output           sd_sec_read_end,
	input            sd_sec_write,
	input[31:0]      sd_sec_write_addr,
	input[7:0]       sd_sec_write_data,
	output           sd_sec_write_data_req,
	output           sd_sec_write_end,

	output reg[15:0] spi_clk_div,
	output reg       cmd_req,
	input            cmd_req_ack,
	input            cmd_req_error,
	output reg[47:0] cmd,
	output reg[7:0]  cmd_r1,
	output reg[15:0] cmd_data_len,
	output reg       block_read_req,
	input            block_read_valid,
	input[7:0]       block_read_data,
	input            block_read_req_ack,
	output reg       block_write_req,
	output[7:0]      block_write_data,
	input            block_write_data_rd,
	input            block_write_req_ack,
	output [191:0]   init_diagnostics,
    input            block_crc_error,
    input [31:0]     block_crc_diagnostics,
    input [7:0]      response_r1,
    input [31:0]     response_data,
    input block_write_error,output reg sd_sec_write_error
);
reg [127:0] csd;
reg [4:0] csd_count;
reg [6:0] csd_crc;
reg high_capacity,legacy_card;
reg [32:0] capacity_base;
reg [4:0] capacity_shift;
reg [25:0] init_timer;
// Preserve the first failing init stage without changing the SD transaction.
reg [4:0] init_fail_stage;
reg [2:0] init_fail_reason;
function [6:0] crc_byte;
 input [6:0] crc; input [7:0] data; integer k;reg [6:0] c;
 begin c=crc;for(k=7;k>=0;k=k-1)begin
   if(c[6]^data[k])c={c[5:0],1'b0}^7'h09;else c={c[5:0],1'b0};
 end crc_byte=c;end
endfunction
reg[7:0] read_data;
reg[31:0] timer;

localparam S_IDLE               = 0;
localparam S_CMD0               = 1;
localparam S_CMD8               = 2;
localparam S_CMD55              = 3;
localparam S_CMD41              = 4;
localparam S_CMD17              = 5;
localparam S_READ               = 6;
localparam S_CMD24              = 7;
localparam S_WRITE              = 8;
localparam S_ERR                = 14;
localparam S_WRITE_END          = 15;
localparam S_READ_END           = 16;
localparam S_WAIT_READ_WRITE    = 17;
localparam S_CMD16              = 18;
localparam S_CMD9=19,S_CSD_READ=20,S_CSD_CHECK=21,S_INIT_FAIL=22,S_CMD59=23;
localparam S_CMD58=24,S_OCR_CHECK=25,S_CAPACITY=26;

reg[4:0]                       state;
assign init_diagnostics={{high_capacity,legacy_card,1'b0,init_error,sd_init_done,cmd_req_error,
 init_fail_reason,(init_error ? init_fail_stage : state),cmd[45:40],csd_count,csd_crc},
 block_crc_diagnostics,csd};
reg[31:0]                      sec_addr;
assign sd_sec_read_data_valid = (state == S_READ) && block_read_valid;
assign sd_sec_read_data = block_read_data;
assign sd_sec_read_end = (state == S_READ_END);
assign sd_sec_write_data_req = (state == S_WRITE) && block_write_data_rd;
assign block_write_data = sd_sec_write_data;
assign sd_sec_write_end = (state == S_WRITE_END);

always@(posedge clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		card_sectors<=0;init_error<=0;block_read_len<=512;csd<=0;csd_count<=0;csd_crc<=0;init_timer<=0;
        high_capacity<=0;legacy_card<=0;capacity_base<=0;capacity_shift<=0;
        init_fail_stage<=0;init_fail_reason<=0;
		state <= S_IDLE;
		cmd_req <= 1'b0;
		cmd_data_len <= 16'd0;
		cmd_r1 <= 8'd0;
		cmd <= 48'd0;
		spi_clk_div <= SPI_LOW_SPEED_DIV[15:0];
		block_write_req <= 1'b0;
		block_read_req <= 1'b0;
		sec_addr <= 32'd0;
		sd_init_done <= 1'b0;sd_sec_write_error<=0;
	end
	else if(!sd_init_done && !init_error && init_timer>=50000000)begin
        init_error<=1;init_fail_stage<=state;init_fail_reason<=1;
        cmd_req<=0;block_read_req<=0;state<=S_INIT_FAIL;
    end
	else begin
		if(!sd_init_done && !init_error)init_timer<=init_timer+1'b1;
		case(state)
			S_IDLE:
			begin
				state <= S_CMD0;
				sd_init_done <= 1'b0;
				spi_clk_div <= SPI_LOW_SPEED_DIV[15:0];
			end
			S_CMD0:
			begin
				if(cmd_req_ack & ~cmd_req_error)
				begin
					state <= S_CMD8;
					cmd_req <= 1'b0;
				end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd0;
					cmd_r1 <= 8'h01;
					cmd <= {8'd0,8'h00,8'h00,8'h00,8'h00,8'h95};
				end
			end
			S_CMD8:
			begin
                if(cmd_req_ack)begin
                    cmd_req<=0;
                    if(cmd_req_error && response_r1==8'h05)begin legacy_card<=1;state<=S_CMD55;end
                    else if(!cmd_req_error && response_data==32'h000001aa)begin legacy_card<=0;state<=S_CMD55;end
                    else begin init_error<=1;init_fail_stage<=state;init_fail_reason<=2;state<=S_INIT_FAIL;end
                end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd4;
					cmd_r1 <= 8'h01;
					cmd <= {8'd8,8'h00,8'h00,8'h01,8'haa,8'h87};
				end
			end
			S_CMD55:
			begin
				if(cmd_req_ack & ~cmd_req_error)
				begin
					state <= S_CMD41;
					cmd_req <= 1'b0;
				end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd0;
					cmd_r1 <= 8'h01;
					cmd <= {8'd55,8'h00,8'h00,8'h00,8'h00,8'hff};
				end
			end
			S_CMD41:
			begin
				if(cmd_req_ack & ~cmd_req_error)
				begin
					state <= S_CMD58;
					cmd_req <= 1'b0;
					sd_init_done <= 1'b0;
					spi_clk_div <= SPI_LOW_SPEED_DIV[15:0];
				end
				else if(cmd_req_ack)
				begin
					state <= S_CMD55;
                    cmd_req<=0;
				end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd0;
					cmd_r1 <= 8'h00;
					cmd <= {8'd41,(legacy_card ? 32'd0 : 32'h40000000),8'hff};
				end
			end
            S_CMD58:begin
                if(cmd_req_ack)begin
                    cmd_req<=0;
                    if(cmd_req_error)begin init_error<=1;init_fail_stage<=state;init_fail_reason<=2;state<=S_INIT_FAIL;end
                    else state<=S_OCR_CHECK;
                end else begin cmd_req<=1;cmd_data_len<=4;cmd_r1<=0;cmd<={8'd58,32'd0,8'hff};end
            end
            S_OCR_CHECK:begin
                if(!response_data[31] || (response_data[23:15]&9'h1ff)==0 || (legacy_card && response_data[30]))begin
                    init_error<=1;init_fail_stage<=state;init_fail_reason<=4;state<=S_INIT_FAIL;
                end else begin
                    high_capacity<=response_data[30];state<=response_data[30] ? S_CMD59 : S_CMD16;
                end
            end
			S_CMD16:
			begin
				if(cmd_req_ack & ~cmd_req_error)
				begin
					state <= S_CMD59;
					cmd_req <= 1'b0;
					sd_init_done <= 1'b0;
					spi_clk_div <= SPI_LOW_SPEED_DIV[15:0];
				end
				else if(cmd_req_ack)
				begin
                    cmd_req<=0;init_error<=1;init_fail_stage<=state;init_fail_reason<=2;state<=S_INIT_FAIL;
				end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd0;
					cmd_r1 <= 8'h00;
					cmd <= {8'd16,32'd512,8'hff};
				end
			end			
            S_CMD59:begin
                if(cmd_req_ack)begin
                    cmd_req<=0;
                    if(cmd_req_error)begin init_error<=1;init_fail_stage<=state;init_fail_reason<=2;state<=S_INIT_FAIL;end
                    else state<=S_CMD9;
                end else begin cmd_req<=1;cmd_data_len<=0;cmd_r1<=0;cmd<={8'd59,32'd1,8'hff};end
            end
            S_CMD9:begin
                if(cmd_req_ack)begin
                    cmd_req<=0;
                    if(cmd_req_error)begin init_error<=1;init_fail_stage<=state;init_fail_reason<=2;state<=S_INIT_FAIL;end
                    else begin csd_count<=0;csd<=0;csd_crc<=0;block_read_len<=16;state<=S_CSD_READ;end
                end else begin cmd_req<=1;cmd_data_len<=0;cmd_r1<=0;cmd<={8'd9,32'd0,8'hff};end
            end
            S_CSD_READ:begin
                if(block_read_valid)begin
                    csd<={csd[119:0],block_read_data};csd_count<=csd_count+1'b1;
                    if(csd_count<15)csd_crc<=crc_byte(csd_crc,block_read_data);
                end
                if(block_read_req_ack)begin
                    block_read_req<=0;
                    if(block_crc_error)begin init_error<=1;init_fail_stage<=state;init_fail_reason<=7;state<=S_INIT_FAIL;end
                    else state<=S_CSD_CHECK;
                end
                else block_read_req<=1;
            end
            S_CSD_CHECK:begin
                block_read_len<=512;
                // Some SPI cards expose a zero register CRC7 field. Accept it
                // only after the full 16-byte CSD transfer passed CRC16 above.
                if(csd_count!=16 || csd[127:126]!={1'b0,high_capacity} ||
                   (high_capacity ? csd[83:80]!=9 : (csd[83:80]<9 || csd[83:80]>11)) ||
                   !csd[0] || (csd[7:1]!=0 && csd_crc!=csd[7:1]))begin
                    init_error<=1;init_fail_stage<=state;
                    init_fail_reason<=csd_count!=16 ? 3 : csd[127:126]!={1'b0,high_capacity} ? 4 :
                      (high_capacity ? csd[83:80]!=9 : (csd[83:80]<9 || csd[83:80]>11)) ? 5 : !csd[0] ? 6 : 7;
                    state<=S_INIT_FAIL;
                end else begin
                    capacity_base<=high_capacity ? {11'd0,csd[69:48]}+33'd1 : {21'd0,csd[73:62]}+33'd1;
                    capacity_shift<=high_capacity ? 5'd10 : {2'd0,csd[49:47]}+{1'b0,csd[83:80]}-5'd7;
                    state<=S_CAPACITY;
                end
            end
            S_CAPACITY:begin
                if(capacity_base==0 || (!high_capacity && (capacity_base<<capacity_shift)>33'd4194304))begin
                    init_error<=1;init_fail_stage<=state;init_fail_reason<=4;state<=S_INIT_FAIL;
                end else begin card_sectors<=capacity_base<<capacity_shift;sd_init_done<=1;state<=S_WAIT_READ_WRITE;end
            end
            S_INIT_FAIL:begin init_error<=1;sd_init_done<=0;cmd_req<=0;block_read_req<=0;block_write_req<=0;end
			S_WAIT_READ_WRITE:
			begin
				if(sd_sec_write ==  1'b1)
				begin
					state <= S_CMD24;
					sec_addr <= sd_sec_write_addr;
                    sd_sec_write_error<=0;
				end
				else if(sd_sec_read == 1'b1)
				begin
					state <= S_CMD17;
					sec_addr <= sd_sec_read_addr;
				end

				spi_clk_div <= SPI_HIGH_SPEED_DIV[15:0];
			end
			S_CMD24:
			begin
				if(cmd_req_ack && cmd_req_error)begin
                 cmd_req<=0;sd_sec_write_error<=1;state<=S_WRITE_END;
                end else if(cmd_req_ack & ~cmd_req_error)
				begin
					state <= S_WRITE;
					cmd_req <= 1'b0;
				end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd0;
					cmd_r1 <= 8'h00;
					cmd <= {8'd24,(high_capacity ? sec_addr : {sec_addr[22:0],9'd0}),8'hff};

				end
			end
			S_WRITE:
			begin
				if(block_write_req_ack == 1'b1)
				begin
					block_write_req <= 1'b0;
					state <= S_WRITE_END;
                    sd_sec_write_error<=block_write_error;
				end
				else
					block_write_req <= 1'b1;
			end
			S_CMD17:
			begin
				if(cmd_req_ack & ~cmd_req_error)
				begin
					state <= S_READ;
					cmd_req <= 1'b0;
				end
				else
				begin
					cmd_req <= 1'b1;
					cmd_data_len <= 16'd0;
					cmd_r1 <= 8'h00;
					cmd <= {8'd17,(high_capacity ? sec_addr : {sec_addr[22:0],9'd0}),8'hff};
				end
			end
			S_READ:
			begin
				if(block_read_req_ack)
				begin
					state <= S_READ_END;
					block_read_req <= 1'b0;
				end
				else
				begin
					block_read_req <= 1'b1;
				end
			end
			S_WRITE_END:
			begin
				state <= S_WAIT_READ_WRITE;
			end
			S_READ_END:
			begin
				state <= S_WAIT_READ_WRITE;
			end
			default:
				state <= S_IDLE;
		endcase
	end
end
endmodule
