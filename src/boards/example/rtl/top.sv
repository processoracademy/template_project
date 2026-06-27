`include "hs_macro.sv"
module example_top #(
    parameter integer REF_CLK_PPS = 100_000_000,
    parameter integer NUM_OF_DOMAINS = 3

)(
    input ref_clk_i,
    input user_rst_i

    // Add your own pins here
);

// `SIM_DEBUG defined in your testbench so you can have simulation-only varients of block-box vendor-locked IP
    wire buffered_ref_clk;
    `ifdef SIM_DEBUG
        assign buffered_ref_clk = ref_clk_i;
    `else
        clk_buf ref_clk_buf (
            .inclk  (ref_clk_i),
            .outclk (buffered_ref_clk)
        );
    `endif

    wire                      async_rst;
    wire                      pll_locked;
    wire [NUM_OF_DOMAINS-1:0] clks;
    wire [NUM_OF_DOMAINS-1:0] reset_polarity = {NUM_OF_DOMAINS{1'b1}};
    // Connect this to signals synchronous to each clock domain to force a reset of that domain.
    wire [NUM_OF_DOMAINS-1:0] force_sync_reset = '0;
    common_p::clk_dom_s       clk_doms [NUM_OF_DOMAINS-1:0];
    reset_and_clock_control #(
        .CLK_PPS       (REF_CLK_PPS),
        .NUM_OF_DOMAINS(3)
    ) reset_and_clock_control (
        .user_reset_ref_clk_i(buffered_ref_clk),
        .user_reset_n_i      (user_rst_i),
        .async_rst_o         (async_rst),
        .pll_clk_locked_i    (pll_locked),
        .controlled_clk_i    (clks),
        .reset_polarity_i    (reset_polarity),
        .force_sync_reset_i  (force_sync_reset),
        .clk_doms_o          (clk_doms)
    );

    `ifdef SIM_DEBUG
        sim_pll #(
            .NUM_OF_DOMAINS(NUM_OF_DOMAINS)
        ) sim_pll (
            .ref_clk_i    (buffered_ref_clk),
            .ref_clk_rst_i(user_rst_i),
            .clks_o       (clks),
            .clk_locked_o (pll_locked)
        );
    `else
        sys_pll clock_40_generation (
            .rst     (async_rst),
            .refclk  (buffered_ref_clk),
            .outclk_0(clks[0]),
            .outclk_1(clks[1]),
            .outclk_2(clks[2]),
            .locked  (pll_locked)
        );
    `endif

// Example Top Level that uses 3 clock domains
    your_top_level your_top_level (
        .high_speed_io_clk_dom_i(clk_doms[0]),
        .sys_clk_dom_i          (clk_doms[1]),
        .low_speed_io_clk_dom_i (clk_doms[2]),
        // Your other pins here
    );

endmodule : example_top
