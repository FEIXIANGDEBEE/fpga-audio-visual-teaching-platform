// PLL divisors retained from official clk_wize.v (50 -> 125 and 25 MHz).
// Added lock output; unused outputs explicitly disconnected rather than sharing 'open'.
module video_pll(input wire refclk, input wire reset,
    output wire serial_clk, output wire pixel_clk, output wire locked,input wire standby);
    wire serial_raw;
    wire [4:0] clocks;
    assign serial_raw = clocks[0];
    assign pixel_clk = clocks[1];
    // Internal C0 feedback avoids uncompensated local feedback routing.
    assign serial_clk = serial_raw;
    EG_PHY_PLL #(
        .DPHASE_SOURCE("DISABLE"), .DYNCFG("DISABLE"), .FIN("50.000000"),
        .FEEDBK_MODE("NORMAL"), .FEEDBK_PATH("VCO_PHASE_0"), .STDBY_ENABLE("ENABLE"),
        .PLLRST_ENA("ENABLE"), .SYNC_ENABLE("DISABLE"),
        .GMC_GAIN(2), .ICP_CURRENT(9), .KVCO(2), .LPF_CAPACITOR(1), .LPF_RESISTOR(8),
        .REFCLK_DIV(2), .FBCLK_DIV(40),
        .CLKC0_ENABLE("ENABLE"), .CLKC0_DIV(8), .CLKC0_CPHASE(7), .CLKC0_FPHASE(0),
        .CLKC1_ENABLE("ENABLE"), .CLKC1_DIV(40), .CLKC1_CPHASE(39), .CLKC1_FPHASE(0)
    ) pll_inst(
        .refclk(refclk), .reset(reset), .stdby(standby), .extlock(locked),
        .load_reg(1'b0), .psclk(1'b0), .psdown(1'b0), .psstep(1'b0),
        .psclksel(3'b000), .psdone(), .dclk(1'b0), .dcs(1'b0), .dwe(1'b0),
        .di(8'b0), .daddr(6'b0), .do(), .fbclk(1'b0), .clkc(clocks)
    );
endmodule
