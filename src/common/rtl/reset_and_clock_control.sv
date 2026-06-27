module reset_and_clock_control #(
    parameter integer NUM_OF_DOMAINS = 5,
    parameter integer REF_CLK_PPS = 100_000_000,
    parameter integer POWER_ON_RESET_DELAY_MS = 10,
    parameter integer RESET_DURATION_MS = 250,
    // How long you want to delay `powered_up` after lowering `ref_sync_rst`.
    // `powered_up` gates the `pll_clk_locked_i` to enforce a minimum amount of post-reset delay.
    parameter integer POST_RESET_DELAY_MS = 150
)(
    input                      user_reset_ref_clk_i,
    input                      user_reset_n_i,
    output                     ref_sync_rst,

    input                      pll_clk_locked_i,

    input [NUM_OF_DOMAINS-1:0] controlled_clk_i,
    input [NUM_OF_DOMAINS-1:0] reset_polarity_i,
    input [NUM_OF_DOMAINS-1:0] force_sync_reset_i,

    output common_p::clk_dom_s clk_doms_o [NUM_OF_DOMAINS-1:0]
);

    wire powered_up;
    reset_control #(
        .REF_CLK_PPS            (REF_CLK_PPS),
        .POWER_ON_RESET_DELAY_MS(POWER_ON_RESET_DELAY_MS),
        .RESET_DURATION_MS      (RESET_DURATION_MS),
        .POST_RESET_DELAY_MS    (POST_RESET_DELAY_MS)
    ) reset_control (
        .user_reset_ref_clk_i(user_reset_ref_clk_i),
        .user_reset_n_i      (user_reset_n_i),
        .ref_sync_rst        (ref_sync_rst),
        .powered_up          (powered_up)
    );

    wire gated_clk_lock = pll_clk_locked_i && powered_up;
    genvar i;
    generate
        for (i = 0; i < NUM_OF_DOMAINS; i = i + 1) begin : dom_gen
            domain_control #(
                .SYNC_RESET_DURATION  (4),
                .CLOCK_ENABLE_DELAY   (4)
            ) domain_control (
                .controlling_clk_i (user_reset_ref_clk_i),
                .domain_enable_i   (gated_clk_lock),
                .async_rst_i       (ref_sync_rst),
                .controlled_clk_i  (controlled_clk_i[i]),
                .reset_polarity_i  (reset_polarity_i[i]),
                .force_sync_reset_i(force_sync_reset_i[i]),
                .clk_dom_o         (clk_doms_o[i])
            );
        end
    endgenerate

endmodule : reset_and_clock_control
