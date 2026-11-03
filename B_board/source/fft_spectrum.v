`timescale 1ns/1ps

// 512-point real input: Hann on capture, bit-reversed writes
// Nine radix-2 stages share a butterfly, then scan bins 1..256 once.
// LOG_BANDS gives the low end finer bands; default groups sixteen bins.
module fft_spectrum #(
    parameter integer N = 512,
    parameter integer BAND_SHIFT = 16,
    parameter integer DATA_W = 28,
    parameter integer LOG_BANDS = 0
) (
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [31:0] window_id_in,
    input wire sample_valid,
    output wire sample_ready,
    input wire signed [15:0] sample_data,
    output reg busy,
    output reg done,
    output reg [31:0] result_window_id,
    output reg band_valid,
    output reg [3:0] band_index,
    output reg [31:0] band_energy,
    output reg band_last,
    output reg [31:0] latency_cycles,
    input wire enable,output reg [8:0] peak_bin,output wire [31:0] peak_magnitude,output reg [31:0] saturation_count,
    output reg [31:0] error_count,
    // Match A filter: 0 bypasses weights, 1..3 use |H(k)| in Q15
    // Those tables occupy the spare half of the coefficient ROM
    input wire [1:0] weight_mode
);
    localparam [4:0] ST_IDLE=4'd0, ST_CAPTURE=4'd1,
                     ST_FFT_RD_A=4'd2, ST_FFT_RD_A_WAIT=4'd3,
                     ST_FFT_RD_B_WAIT=4'd4, ST_FFT_CALC=4'd5,
                     ST_FFT_WR_A=4'd6, ST_FFT_WR_B=4'd7,
                     ST_BAND_INIT=4'd8, ST_BAND_RD=4'd9,
                     ST_BAND_WAIT=4'd10, ST_BAND=4'd11,
                     ST_BAND_ADV=4'd12, ST_DONE=4'd13,ST_ROT=5'd14,ST_SCALE=5'd15,ST_MAG=5'd16,ST_CMUL_BD=5'd17,ST_CMUL_AD=5'd18,ST_CMUL_BC=5'd19,ST_MAG_IMAG=5'd20,ST_MUL_CAPTURE=5'd21,ST_MUL_PRODUCT=5'd22,ST_MUL_APPLY=5'd23;
    localparam integer LOGN = 9;

    reg [4:0] state;
    reg [8:0] sample_count;
    reg [3:0] stage;
    reg [9:0] group_base;
    reg [8:0] butterfly_j;
    reg [8:0] bin_index;
    reg [3:0] band_bin_count;
    // Band ends: 1,2,3,4,5,6,7,8,10,14,20,28,44,68,116,256.
    // Explicit endpoints keep a variable table/divider out of the scan path
    wire band_end = LOG_BANDS ? (bin_index<=9'd8 || bin_index==9'd10 ||
        bin_index==9'd14 || bin_index==9'd20 || bin_index==9'd28 ||
        bin_index==9'd44 || bin_index==9'd68 || bin_index==9'd116 ||
        bin_index==9'd256) : band_bin_count==4'd15;
    reg [63:0] band_acc;
    reg [31:0] cycle_count;

    reg [8:0] ram_raddr, ram_waddr;
    localparam integer PROD_W = DATA_W + 16;
    reg signed [DATA_W-1:0] ram_wdata_real, ram_wdata_imag;
    reg ram_we_real, ram_we_imag;
    wire signed [DATA_W-1:0] ram_rdata_real, ram_rdata_imag;
    fft_ram #(.ADDR_W(9), .DATA_W(DATA_W), .DEPTH(N)) real_ram(
        .clk(clk), .read_enable(reset_n), .we(ram_we_real), .waddr(ram_waddr), .wdata(ram_wdata_real),
        .raddr(ram_raddr), .rdata(ram_rdata_real));
    fft_ram #(.ADDR_W(9), .DATA_W(DATA_W), .DEPTH(N)) imag_ram(
        .clk(clk), .read_enable(reset_n), .we(ram_we_imag), .waddr(ram_waddr), .wdata(ram_wdata_imag),
        .raddr(ram_raddr), .rdata(ram_rdata_imag));
    wire [8:0] tw_idx_w = butterfly_j << (8-stage);
    wire signed [15:0] coeff_a,coeff_b;
    wire [8:0] hann_next = sample_count + ((enable && sample_valid && sample_ready && sample_count!=511) ? 9'd1 : 9'd0);
    // Latch with the window ID; do not change weights halfway through a scan
    reg [1:0] wmode;
    reg weighting;
    // RD presents the weight, WAIT latches it with the bin. Bin256 uses
    // offset0; band states never need a twiddle read on this port.
    wire [10:0] coeff_address_a = (state==ST_IDLE || state==ST_DONE) ? 11'd0 :
        state==ST_CAPTURE ? {2'b00,hann_next} :
        state==ST_BAND_RD ? {1'b1,wmode,bin_index[7:0]} : {3'b010,tw_idx_w[7:0]};
    wire [10:0] coeff_address_b = {3'b011,tw_idx_w[7:0]};
    // N=512 shares one synchronous ROM across both coefficient ports.
    // The read states already give twiddles a clock to arrive.
    generate if(N==512)begin:g_coefficients
        EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),
          .DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
          .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K"),
          .INIT_FILE("scene_fft_coefficients.dath")) coefficient_rom(
          .doa(coeff_a),.dob(coeff_b),.dia(16'd0),.dib(16'd0),.cea(reset_n),.ceb(reset_n),
          .ocea(1'b1),.oceb(1'b1),.clka(clk),.clkb(clk),.wea(1'b0),.web(1'b0),
          .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(coeff_address_a),.addrb(coeff_address_b));
    end else begin:g_other_n
        reg signed [15:0] hann_rom[0:N-1],tw_cos_rom[0:(N/2)-1],tw_sin_rom[0:(N/2)-1];
        initial begin
            $readmemh("hann_q15.hex",hann_rom);$readmemh("tw_cos_q15.hex",tw_cos_rom);$readmemh("tw_sin_q15.hex",tw_sin_rom);
        end
        assign coeff_a=state==ST_CAPTURE ? hann_rom[sample_count] : tw_cos_rom[tw_idx_w];
        assign coeff_b=tw_sin_rom[tw_idx_w];
    end endgenerate

    function [8:0] bit_reverse9;
        input [8:0] value;
        integer k;
        begin
            for (k=0; k<9; k=k+1) bit_reverse9[k] = value[8-k];
        end
    endfunction

    wire [9:0] half_w = (10'd1 << stage);
    wire [9:0] idx_a_w = group_base + butterfly_j;
    wire [9:0] idx_b_w = idx_a_w + half_w;
    assign sample_ready = (state == ST_CAPTURE) && busy && enable;

    reg signed [31:0] sample_product;
    reg signed [PROD_W:0] accumulator_real,accumulator_imag;
    wire signed [PROD_W:0] rotated_real=accumulator_real,rotated_imag=accumulator_imag;
    reg signed [DATA_W-1:0] a_r, a_i, b_r, b_i;
    reg signed [DATA_W-1:0] temp_r_q, temp_i_q;
    reg signed [15:0] tw_c_q, tw_s_q;
    // No butterflies during the band scan: b_r/b_i can hold the bin pair
    // with the same signed width, so there is no second 28-bit pair to keep.
    wire signed [DATA_W-1:0] band_real_q=b_r, band_imag_q=b_i;
    reg signed [DATA_W-1:0] multiply_a,multiply_b;
    reg [2:0] multiply_kind;
    wire signed [2*DATA_W-1:0] shared_product;
    wire multiply_last;
    // Four native 18x18 DSPs, full signed result. Keep all 28 advances of
    // the earlier add/shift schedule so the surrounding FSM timing stays put.
    dsp_multiply #(.W(DATA_W)) exact_multiply(
      .clk(clk),.enable(enable),.load(state==ST_MUL_CAPTURE),.advance(state==ST_MUL_PRODUCT),
      .a(multiply_a),.b(multiply_b),.product(shared_product),.last(multiply_last));
    wire signed [PROD_W-1:0] complex_product=shared_product[PROD_W-1:0];
    wire signed [PROD_W:0] extended_product={complex_product[PROD_W-1],complex_product};
    // Weighting borrows kind0/3 for BR*W / BI*W; tw_c_q holds W.
    // W is 0..32767, hence (B*W)>>>15 still fits DATA_W bits.
    wire signed [DATA_W-1:0] weighted_part=shared_product[DATA_W+14:15];
    // Hold operands through the whole multiply, including enable stalls.
    // Sign-extend Q15 twiddles to DATA_W (28 in production).
    // kinds 0..5: BR*COS, BI*SIN, BR*SIN, BI*COS, BR^2, BI^2
    // Parity picks the B operand; bit2 squares it; XOR picks SIN/COS.
    // That decode avoids full-width four-way masks and duplicate bin regs.
    wire signed [DATA_W-1:0] cos_extended={{(DATA_W-16){tw_c_q[15]}},tw_c_q};
    wire signed [DATA_W-1:0] sin_extended={{(DATA_W-16){tw_s_q[15]}},tw_s_q};
    always @*begin
        multiply_a=multiply_kind[0] ? b_i:b_r;
        multiply_b=multiply_kind[2] ? multiply_a:
                   (multiply_kind[0]^multiply_kind[1]) ? sin_extended:cos_extended;
    end

    reg signed [(2*DATA_W)-1:0] mag2_tmp,mag_sum;
    reg [63:0] peak_power;
    assign peak_magnitude=(peak_power>>BAND_SHIFT)>64'hffffffff ? 32'hffffffff : peak_power>>BAND_SHIFT;
    reg [(2*DATA_W)+3:0] band_sum_tmp;
    wire signed [31:0] sample_ext = {{16{sample_data[15]}}, sample_data};
    wire signed [31:0] hann_ext = {{16{coeff_a[15]}}, coeff_a};

    // WR_A/WR_B never overlap. Add/subtract wraps modulo 2**DATA_W;
    // sharing the adder must preserve that truncation, including overflow.
    wire butterfly_subtract=(state==ST_FFT_WR_B);
    wire [DATA_W-1:0] butterfly_real=a_r+(temp_r_q ^ {DATA_W{butterfly_subtract}})+butterfly_subtract;
    wire [DATA_W-1:0] butterfly_imag=a_i+(temp_i_q ^ {DATA_W{butterfly_subtract}})+butterfly_subtract;

    always @* begin
        ram_raddr = 9'd0;
        ram_waddr = 9'd0;
        ram_wdata_real = 28'sd0;
        ram_wdata_imag = 28'sd0;
        ram_we_real = 1'b0;
        ram_we_imag = 1'b0;
        if (enable && state == ST_CAPTURE && sample_valid && sample_ready) begin
            ram_waddr = bit_reverse9(sample_count);
            ram_wdata_real = (sample_ext * hann_ext) >>> 15;
            ram_we_real = 1'b1;
            ram_we_imag = 1'b1;
        end else if (state == ST_FFT_RD_A) begin
            ram_raddr = idx_a_w[8:0];
        end else if (state == ST_FFT_RD_A_WAIT) begin
            ram_raddr = idx_b_w[8:0];
        end else if (enable && state == ST_FFT_WR_A) begin
            ram_waddr = idx_a_w[8:0];
            ram_wdata_real = butterfly_real;
            ram_wdata_imag = butterfly_imag;
            ram_we_real = 1'b1;
            ram_we_imag = 1'b1;
        end else if (enable && state == ST_FFT_WR_B) begin
            ram_waddr = idx_b_w[8:0];
            ram_wdata_real = butterfly_real;
            ram_wdata_imag = butterfly_imag;
            ram_we_real = 1'b1;
            ram_we_imag = 1'b1;
        end else if (state == ST_BAND_RD) begin
            ram_raddr = bin_index;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state<=ST_IDLE; busy<=0; done<=0; result_window_id<=0;
            band_valid<=0; band_index<=0; band_energy<=0; band_last<=0;
            latency_cycles<=0; error_count<=0;peak_bin<=0;peak_power<=0;saturation_count<=0;mag_sum<=0; sample_count<=0;
            stage<=0; group_base<=0; butterfly_j<=0; bin_index<=0;
            band_bin_count<=0; band_acc<=0; cycle_count<=0;
            temp_r_q<=0; temp_i_q<=0; tw_c_q<=0; tw_s_q<=0;
            multiply_kind<=0;wmode<=0;weighting<=0;
        end else begin
            band_valid <= 1'b0;
            band_last <= 1'b0;

            if (busy && enable) cycle_count <= cycle_count + 1'b1;

            if(enable)case (state)
                ST_IDLE, ST_DONE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        result_window_id <= window_id_in;wmode<=weight_mode;
                        sample_count <= 0;peak_bin<=0;peak_power<=0;
                        cycle_count <= 0;
                        state <= ST_CAPTURE;
                    end
                end

                ST_CAPTURE: begin
                    if (sample_valid && sample_ready) begin
                        if (sample_count == 9'd511) begin
                            stage <= 0;
                            group_base <= 0;
                            butterfly_j <= 0;
                            state <= ST_FFT_RD_A;
                        end else sample_count <= sample_count + 1'b1;
                    end
                end

                // Serialized RAM reads/writes; shared multiplies run between
                // them. These access states are not the full butterfly latency.
                ST_FFT_RD_A: begin
                    state <= ST_FFT_RD_A_WAIT;
                end
                ST_FFT_RD_A_WAIT: begin
                    a_r <= ram_rdata_real;
                    a_i <= ram_rdata_imag;
                    state <= ST_FFT_RD_B_WAIT;
                end
                ST_FFT_RD_B_WAIT: begin
                    b_r <= ram_rdata_real;
                    b_i <= ram_rdata_imag;
                    tw_c_q <= coeff_a;
                    tw_s_q <= coeff_b;
                    multiply_kind<=0;state <= ST_MUL_CAPTURE;
                end
                ST_MUL_CAPTURE:state<=ST_MUL_PRODUCT;
                ST_MUL_PRODUCT:if(multiply_last)state<=ST_MUL_APPLY;
                ST_MUL_APPLY:begin
                 case(multiply_kind)
                  // Weighting does not consume these accumulators. The next
                  // window's first butterfly overwrites them with kind0/2.
                  0:begin accumulator_real<=extended_product;state<=ST_MUL_CAPTURE;
                     if(weighting)begin b_r<=weighted_part;multiply_kind<=3;end else multiply_kind<=1;end
                  1:begin accumulator_real<=accumulator_real-extended_product;multiply_kind<=2;state<=ST_MUL_CAPTURE;end
                  2:begin accumulator_imag<=extended_product;multiply_kind<=3;state<=ST_MUL_CAPTURE;end
                  3:begin accumulator_imag<=accumulator_imag+extended_product;
                     if(weighting)begin b_i<=weighted_part;weighting<=0;multiply_kind<=4;state<=ST_MUL_CAPTURE;end else state<=ST_ROT;end
                  4:begin mag_sum<=shared_product;multiply_kind<=5;state<=ST_MUL_CAPTURE;end
                  5:begin mag_sum<=mag_sum+shared_product;state<=ST_MAG;end
                  default:state<=ST_IDLE;
                 endcase
                end
                ST_ROT:begin
                    state<=ST_SCALE;
                end
                ST_SCALE:begin
                    if((rotated_real>>>15)>((1<<(DATA_W-1))-1) || (rotated_real>>>15)<-(1<<(DATA_W-1)) || (rotated_imag>>>15)>((1<<(DATA_W-1))-1) || (rotated_imag>>>15)<-(1<<(DATA_W-1)))error_count<=error_count+1'b1;
                    temp_r_q <= rotated_real >>> 15;
                    temp_i_q <= rotated_imag >>> 15;
                    state <= ST_FFT_WR_A;
                end
                ST_FFT_WR_A: begin
                    state <= ST_FFT_WR_B;
                end
                ST_FFT_WR_B: begin
                    if (butterfly_j == half_w-1) begin
                        butterfly_j <= 0;
                        if (group_base + (half_w << 1) >= N) begin
                            if (stage == LOGN-1) begin
                                state <= ST_BAND_INIT;
                            end else begin
                                stage <= stage + 1'b1;
                                group_base <= 0;
                                state <= ST_FFT_RD_A;
                            end
                        end else begin
                            group_base <= group_base + (half_w << 1);
                            state <= ST_FFT_RD_A;
                        end
                    end else begin
                        butterfly_j <= butterfly_j + 1'b1;
                        state <= ST_FFT_RD_A;
                    end
                end

                ST_BAND_INIT: begin
                    bin_index <= 1;
                    band_index <= 0;
                    band_bin_count <= 0;
                    band_acc <= 0;
                    state <= ST_BAND_RD;
                end

                ST_BAND_RD: begin
                    state <= ST_BAND_WAIT;
                end

                ST_BAND_WAIT: begin
                    b_r <= ram_rdata_real;
                    b_i <= ram_rdata_imag;
                    tw_c_q <= coeff_a;weighting<=wmode!=0;
                    multiply_kind<=wmode!=0 ? 3'd0:3'd4;state <= ST_MUL_CAPTURE;
                end

                ST_MAG:begin
                    mag2_tmp = mag_sum;
                    if($unsigned(mag2_tmp)>peak_power)begin peak_power<=$unsigned(mag2_tmp);peak_bin<=bin_index;end
                    band_sum_tmp = band_acc + mag2_tmp;
                    if (band_end) begin
                        band_valid <= 1'b1;
                        band_last <= (bin_index == 9'd256);
                        if((band_sum_tmp>>BAND_SHIFT)>32'hffffffff)begin band_energy<=32'hffffffff;saturation_count<=saturation_count+1'b1;end
                        else band_energy <= band_sum_tmp >> BAND_SHIFT;
                        band_acc <= 0;
                        band_bin_count <= 0;
                        if (bin_index == 9'd256) begin
                            latency_cycles <= cycle_count;
                            done <= 1'b1;
                            busy <= 1'b0;
                            state <= ST_DONE;
                        end else begin
                            bin_index <= bin_index + 1'b1;
                            state <= ST_BAND_ADV;
                        end
                    end else begin
                        band_acc <= band_sum_tmp;
                        band_bin_count <= band_bin_count + 1'b1;
                        bin_index <= bin_index + 1'b1;
                        state <= ST_BAND_RD;
                    end
                end

                ST_BAND_ADV: begin
                    band_index <= band_index + 1'b1;
                    state <= ST_BAND_RD;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

module fft_ram #(
    parameter integer ADDR_W = 9,
    parameter integer DATA_W = 28,
    parameter integer DEPTH = 512
) (
    input wire clk,
    input wire we,read_enable,
    input wire [ADDR_W-1:0] waddr,
    input wire signed [DATA_W-1:0] wdata,
    input wire [ADDR_W-1:0] raddr,
    output reg signed [DATA_W-1:0] rdata
);
    (* ram_style = "block" *) reg signed [DATA_W-1:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        if(read_enable) rdata <= mem[raddr];
    end
endmodule
