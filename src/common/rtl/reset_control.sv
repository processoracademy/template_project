module reset_control #(
    parameter integer REF_CLK_PPS = 100_000_000,
    parameter integer POWER_ON_RESET_DELAY_MS = 10,
    parameter integer RESET_DURATION_MS = 250,
    parameter integer POST_RESET_DELAY_MS = 150
)(
    input                      user_reset_ref_clk_i,
    input                      user_reset_n_i,

    output                     ref_sync_rst,
    output                     powered_up
);

    reg  [7:0] power_on_reset_vector_current;
    reg        local_clk_en;
    reg        local_sync_rst;
    wire       power_on_reset_saturation_check = &power_on_reset_vector_current;
    wire       power_on_reset_vector_lsb = power_on_reset_vector_current[0] || ~power_on_reset_saturation_check;
    always_ff @(posedge user_reset_ref_clk_i) begin
        power_on_reset_vector_current <= {power_on_reset_vector_current[6:0], power_on_reset_vector_lsb};
        local_sync_rst <= ~power_on_reset_vector_current[5] && power_on_reset_vector_current[4];
        local_clk_en <= power_on_reset_saturation_check;
    end

    sys_structs::clk_domain clk_dom;
    assign clk_dom.clk = user_reset_ref_clk_i;
    assign clk_dom.clk_en = 1'b1;
    assign clk_dom.sync_rst = local_sync_rst;

    wire clk = clk_dom.clk;
    wire clk_en = clk_dom.clk_en;
    wire sync_rst = clk_dom.sync_rst;

    wire user_reset_pressed;
    monostable_debouncer #(
        .CLK_PPS               (100_000_000),
        .VALIDATION_DURATION_MS(15),
        .REPEAT_INTERVAL_MS    (250),
        .LOCKOUT_DURATION_MS   (15),
        .INPUT_POLARITY        (1'b0),
        .OUTPUT_POLARITY       (1'b1)
    ) reset_debouncer (
        .clk_dom_i       (clk_dom),
        .from_io_i       (user_reset_n_i),
        .pressed_pulse_o (user_reset_pressed),
        .repeated_pulse_o(), // Not Used
        .released_pulse_o()  // Not Used
    );

    typedef enum {
        POWER_ON_RESET_DELAY,
        RESETTING,
        POST_RESET_WAIT,
        POWERED_UP
    } state_e;
    
    state_e        state_current;
    state_e        state_next;
    logic          update_state;
    logic          timer_en;
    logic   [31:0] timer_limit;
    wire           timer_elapsed;
    
    always_comb begin : state_machine
        timer_en = 1'b0;
        timer_limit = POWER_ON_RESET_DELAY_MS;
        case (state_current)
            POWER_ON_RESET_DELAY : begin
                state_next = RESETTING;
                update_state = timer_elapsed;
                timer_en = 1'b1;
            end
            RESETTING : begin
                state_next = POST_RESET_WAIT;
                update_state = timer_elapsed;
                timer_en = 1'b1;
                timer_limit = RESET_DURATION_MS;
            end
            POST_RESET_WAIT : begin
                state_next = POWERED_UP;
                update_state = timer_elapsed;
                timer_en = 1'b1;
                timer_limit = POST_RESET_DELAY_MS;
            end
            POWERED_UP : begin
                state_next = RESETTING;
                update_state = user_reset_pressed;
            end
            default : begin
                state_next = POWER_ON_RESET_DELAY;
                update_state = 1'b1;
            end
        endcase
    end
    
    wire state_trigger = sync_rst || update_state;
    always_ff @(posedge clk) begin
        if (state_trigger) begin
            state_current <= sync_rst
                        ? POWER_ON_RESET_DELAY
                        : state_next;
        end
    end

    watchdog_timer #(
        .CLK_PPS(REF_CLK_PPS),
        .LIMIT_IN_SEC(1'b0)
    ) event_timer (
        .clk_dom_i        (clk_dom),
        .timer_en_i       (timer_en),
        .timer_limit_i    (timer_limit),
        .timer_clear_i    (timer_elapsed),
        .active_duration_o(), // Not Used
        .timer_elapsed_o  (timer_elapsed)
    );

    // Buffering by 4 cycles, allows Quartus (or other tools) more room
    // to use register duplication to help minimize routing/timing issues
    reg  [3:0] reset_vector_current;
    always_ff @(posedge clk) begin
        reset_vector_current <= {reset_vector_current, (state_current == RESETTING)};
    end

endmodule : reset_control
