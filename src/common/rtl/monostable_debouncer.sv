module monostable_debouncer #(
    parameter integer CLK_PPS = 100_000_000,
    parameter integer VALIDATION_DURATION_MS = 15,
    parameter integer REPEAT_INTERVAL_MS = 250, 
    parameter integer LOCKOUT_DURATION_MS = 15,
    // `INPUT_POLARITY` == 1'b1: Active High, Idle Low
    // `INPUT_POLARITY` == 1'b0: Active Low, Idle High
    parameter bit INPUT_POLARITY = 1'b1,
    // `OUTPUT_POLARITY` == 1'b1: Active High Pulse, Idle Low
    // `OUTPUT_POLARITY` == 1'b0: Active Low Pulse, Idle High
    parameter bit OUTPUT_POLARITY = 1'b1
)(
    input common_p::clk_dom_s clk_dom_i,
    input                     from_io_i,
    output              logic pressed_pulse_o,
    output              logic repeated_pulse_o,
    output              logic released_pulse_o
);

    wire clk = clk_dom_i.clk;
    wire clk_en = clk_dom_i.clk_en;
    wire sync_rst = clk_dom_i.sync_rst;

    typedef enum {
        IDLE,
        VALIDATION_WAIT,
        PRESSED,
        HELD,
        RELEASED,
        LOCKED_OUT
    } state_e;
    
    state_e        state_current;
    state_e        state_next;
    logic          update_state;
    logic          timer_en;
    logic   [31:0] timer_limit;
    wire           timer_elapsed;

    wire    io_active = INPUT_POLARITY
                      ? from_io_i
                      : ~from_io_i;
    wire    io_idle = INPUT_POLARITY
                    ? ~from_io_i
                    : from_io_i;

    always_comb begin : state_machine
        timer_en = 1'b0;
        timer_limit = REPEAT_INTERVAL_MS;
        case (state_current)
            IDLE : begin
                state_next = VALIDATION_WAIT;
                update_state = INPUT_POLARITY
                             ? from_io_i
                             : ~from_io_i;
            end
            VALIDATION_WAIT : begin
                state_next = io_active
                           ? PRESSED
                           : IDLE;
                update_state = timer_elapsed;
                timer_en = 1'b1;
                timer_limit = VALIDATION_DURATION_MS;
            end
            PRESSED : begin
                state_next = HELD;
                update_state = 1'b1;
            end
            HELD : begin
                state_next = RELEASED;
                update_state = io_idle;
                timer_en = 1'b1;
            end
            RELEASED : begin
                state_next = LOCKED_OUT;
                update_state = 1'b1;
            end
            LOCKED_OUT : begin
                state_next = IDLE;
                update_state = timer_elapsed;
                timer_en = 1'b1;
                timer_limit = LOCKOUT_DURATION_MS;
            end
            default : begin
                state_next = IDLE;
                update_state = 1'b1;
            end
        endcase
    end
    
    wire state_trigger = sync_rst || update_state;
    always_ff @(posedge clk) begin
        if (state_trigger) begin
            state_current <= sync_rst
                           ? IDLE
                           : state_next;
        end
    end

// Timer
    watchdog_timer #(
        .CLK_PPS(CLK_PPS),
        .LIMIT_IN_SEC(1'b0)
    ) event_timer (
        .clk_dom_i        (clk_dom_i),
        .timer_en_i       (timer_en),
        .timer_limit_i    (timer_limit),
        .timer_clear_i    (timer_elapsed),
        .active_duration_o(), // Not Used
        .timer_elapsed_o  (timer_elapsed)
    );

// Repeat Check
    wire repeat_en = state_current == HELD;
    wire repeat_pulse;
    monostable_full #(
        .BUFFERED(1'b0)
    ) repeat_monostable (
        .clk_dom_i      (clk_dom_i),
        .monostable_en_i(repeat_en),
        .sense_i        (timer_elapsed),
        .prev_o         (), // Not Used
        .posedge_mono_o (repeat_pulse),
        .negedge_mono_o (), // Not Used
        .bothedge_mono_o()  // Not Used
    );

// Output Buffers
    wire output_trigger = sync_rst || clk_en;
    always_ff @(posedge clk) begin
        if (output_trigger) begin
            pressed_pulse_o <= OUTPUT_POLARITY
                             ? state_current == PRESSED
                             : state_current != PRESSED;
            repeated_pulse_o <= OUTPUT_POLARITY
                             ? repeat_pulse
                             : ~repeat_pulse;
            released_pulse_o <= OUTPUT_POLARITY
                             ? state_current == RELEASED
                             : state_current != RELEASED;
        end
    end

endmodule : monostable_debouncer
