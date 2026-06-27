module watchdog_timer #(
    parameter CLK_PPS = 50_000_000,
    parameter bit LIMIT_IN_SEC = 1'b0 // If 0, limit is in ms NOT sec
)(
    input    sys_structs::clk_domain clk_dom_i,

    input                            timer_en_i,
    input                     [31:0] timer_limit_i,
    input                            timer_clear_i,

    output              logic [31:0] active_duration_o,
    // To drop this flag: raise `timer_clear_i` or cause a falling edge on `timer_en_i
    output                     logic timer_elapsed_o
);

    wire clk = clk_dom_i.clk;
    wire clk_en = clk_dom_i.clk_en;
    wire sync_rst = clk_dom_i.sync_rst;

    localparam CYCLES_PER_MS = CLK_PPS / 1000;
    localparam CYCLE_LIMIT = LIMIT_IN_SEC
                           ? (CLK_PPS - 1)
                           : (CYCLES_PER_MS - 1);

    wire disable_detected;
    monostable_full #(
        .BUFFERED(1'b0)
    ) enable_monostable (
        .clk_dom_i      (clk_dom_i),
        .monostable_en_i(1'b1),
        .sense_i        (timer_en_i),
        .prev_o         (), // Not Used
        .posedge_mono_o (), // Not Used
        .negedge_mono_o (disable_detected),
        .bothedge_mono_o()  // Not Used
    );
    wire clear_en = disable_detected || timer_clear_i;

    reg  [31:0] cycle_counter_current;
    wire        cycle_limit_elapsed = cycle_counter_current == CYCLE_LIMIT;
    wire [31:0] cycle_counter_next = (sync_rst || cycle_limit_elapsed || timer_elapsed_o || clear_en)
                                   ? 32'd0
                                   : (cycle_counter_current + 32'd1);
    wire        cycle_counter_trigger = sync_rst
                                     || (clk_en && timer_en_i)
                                     || (clk_en && clear_en);
    always_ff @(posedge clk) begin
        if (cycle_counter_trigger) begin
            cycle_counter_current <= cycle_counter_next;
        end
    end

    wire [31:0] ms_or_sec_counter_next = (sync_rst || timer_elapsed_o || clear_en)
                                ? 32'd0
                                : (active_duration_o + 32'd1);
    wire        ms_or_sec_counter_trigger = sync_rst
                                  || (clk_en && timer_en_i && cycle_limit_elapsed)
                                  || (clk_en && timer_elapsed_o)
                                  || (clk_en && clear_en);
    always_ff @(posedge clk) begin
        if (ms_or_sec_counter_trigger) begin
            active_duration_o <= ms_or_sec_counter_next;
        end
    end

    wire timer_elapse_check = active_duration_o == timer_limit_i;
    wire timer_elapsed_next = ~sync_rst && timer_elapse_check && ~clear_en;
    wire timer_elapsed_trigger = sync_rst
                              || (clk_en && timer_elapse_check && timer_en_i)
                              || (clk_en && clear_en);
    always_ff @(posedge clk) begin
        if (timer_elapsed_trigger) begin
            timer_elapsed_o <= timer_elapsed_next;
        end
    end

endmodule : watchdog_timer
