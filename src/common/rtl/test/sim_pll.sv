module sim_pll #(
    parameter integer NUM_OF_DOMAINS = 5
)(
    input                       ref_clk_i,
    input                       ref_clk_rst_i,
    output [NUM_OF_DOMAINS-1:0] clks_o,
    output                logic clk_locked_o
);

    reg  [NUM_OF_DOMAINS:0] counter_current;
    wire [NUM_OF_DOMAINS:0] counter_next = ref_clk_rst_i
                                         ? NUM_OF_DOMAINS'(0)
                                         : (counter_current + NUM_OF_DOMAINS'(1));
    always_ff @(posedge ref_clk_i) begin
        counter_current <= counter_next;
    end
    assign clks_o = counter_current[NUM_OF_DOMAINS-1:0];

    sys_structs::clk_domain clk_dom;
    assign clk_dom.clk = ref_clk_i;
    assign clk_dom.clk_en = 1'b1;
    assign clk_dom.sync_rst = ref_clk_rst_i;

    // This pulse triggers after every clock has had at least 1 cycle.
    wire locked_pulse;
    monostable_full #(
        .BUFFERED(1'b0)
    ) repeat_monostable (
        .clk_dom_i      (clk_dom),
        .monostable_en_i(1'b1),
        .sense_i        (counter_current[NUM_OF_DOMAINS]),
        .prev_o         (), // Not Used
        .posedge_mono_o (), // Not Used
        .negedge_mono_o (locked_pulse),
        .bothedge_mono_o()  // Not Used
    );

    wire clk_locked_next = ~ref_clk_rst_i && locked_pulse;
    wire clk_locked_trigger = ref_clk_rst_i || locked_pulse;
    always_ff @(posedge ref_clk_i) begin
        if (clk_locked_trigger) begin
            clk_locked_o <= clk_locked_next;
        end
    end

endmodule : sim_pll
