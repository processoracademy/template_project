module domain_control #(
    parameter integer SYNC_RESET_DURATION = 4,
    // How many cycles after the sync_reset drops is there before `clk_dom_o.clk_en` rises.
    parameter integer CLOCK_ENABLE_DELAY = 4
)(
    input                      controlling_clk_i,
    input                      domain_enable_i,
    input                      async_rst_i,

    input                      controlled_clk_i,
    input                      reset_polarity_i,
    input                      force_sync_reset_i,

    output common_p::clk_dom_s clk_dom_o
);

    wire clk = clk_dom_o.clk;
    wire clk_en = clk_dom_o.clk_en;
    wire sync_rst = clk_dom_o.sync_rst;

    wire synchronized_domain_enable;
    cdc_level_synchronizer #(
        .CHAIN_DEPTH       (4),
        .CONFIRMATION_DEPTH(2)
    ) cdc_level_synchronizer (
        .input_clk_i (controlling_clk_i),
        .async_rst_i (async_rst_i),
        .data_i      (domain_enable_i),
        .output_dom_i(clk_dom_o),
        .data_o      (synchronized_domain_enable)
    );

    wire pulsed_enable;
    wire pulsed_disable;
    wire latched_enable;
    monostable_full #(
        .BUFFERED(1'b0)
    ) synchronized_monostable_full (
        .clk_dom_i      (clk_dom_o),
        .monostable_en_i(1'b1),
        .sense_i        (synchronized_domain_enable),
        .prev_o         (latched_enable),
        .posedge_mono_o (), // Not Needed
        .negedge_mono_o (pulsed_enable),
        .bothedge_mono_o(pulsed_disable)  // Not Needed
    );

    // Note: Since this is using the output domain, it can only trigger once the domain is already enabled.
    wire local_pulsed_reset;
    monostable_full #(
        .BUFFERED(1'b0)
    ) force_reset_monostable_full (
        .clk_dom_i      (clk_dom_o),
        .monostable_en_i(1'b1),
        .sense_i        (force_sync_reset_i),
        .prev_o         (), // Not Needed
        .posedge_mono_o (), // Not Needed
        .negedge_mono_o (local_pulsed_reset),
        .bothedge_mono_o()  // Not Needed
    );

// State Machine
    typedef enum logic [1:0] {
        DISABLED     = 2'b00,
        RESETTING    = 2'b01,
        ENABLE_DELAY = 2'b10,
        ENABLED      = 2'b11
    } state_e;
    
    state_e state_current;
    state_e state_next;
    logic   update_state;

    wire    counter_elapsed;

    always_comb begin : state_machine
        unique case (state_current)
            DISABLED : begin
                state_next = RESETTING;
                update_state = pulsed_enable;
            end
            RESETTING : begin
                state_next = ENABLE_DELAY;
                update_state = counter_elapsed;
            end
            ENABLE_DELAY : begin
                state_next = ENABLED;
                update_state = counter_elapsed;
            end
            ENABLED : begin
                state_next = RESETTING;
                update_state = local_pulsed_reset;
            end
        endcase
    end
    
    wire state_trigger = pulsed_disable || update_state;
    always_ff @(posedge clk) begin
        if (state_trigger) begin
            state_current <= pulsed_disable
                           ? DISABLED
                           : state_next;
        end
    end

// Cycle Counter
    localparam LONGER_DURATION = (SYNC_RESET_DURATION > CLOCK_ENABLE_DELAY)
                               ? SYNC_RESET_DURATION
                               : CLOCK_ENABLE_DELAY;
    localparam COUNTER_WIDTH = $clog2(LONGER_DURATION);

    reg    [COUNTER_WIDTH-1:0] cycle_count_current;
    wire   [COUNTER_WIDTH-1:0] counter_limit = (state_current == RESETTING)
                                             ? SYNC_RESET_DURATION
                                             : CLOCK_ENABLE_DELAY;
    assign                     counter_elapsed = counter_limit == cycle_count_current;
    wire   [COUNTER_WIDTH-1:0] cycle_count_next = (pulsed_enable || counter_elapsed || local_pulsed_reset)
                                                ? COUNTER_WIDTH'(0)
                                                : (cycle_count_current + COUNTER_WIDTH'(1));
    wire                       cycle_count_trigger = pulsed_enable
                                                  || (latched_enable && (state_current == RESETTING))
                                                  || (latched_enable && (state_current == ENABLE_DELAY))
                                                  || (latched_enable && local_pulsed_reset);
    always_ff @(posedge clk) begin
        if (cycle_count_trigger) begin
            cycle_count_current <= cycle_count_next;
        end
    end

// Output Buffers
    always_ff @(posedge clk or posedge async_rst_i) begin
        if (async_rst_i) begin
            clk_dom_o.clk_en <= 1'b0;
            clk_dom_o.sync_rst <= ~reset_polarity_i;
        end
        else begin
            clk_dom_o.clk_en <= state_current == ENABLED;
            clk_dom_o.sync_rst <= (state_current == RESETTING)
                                ? ~reset_polarity_i
                                : reset_polarity_i;
        end
    end
    assign clk_dom_o.clk = controlled_clk_i;

endmodule : domain_control
