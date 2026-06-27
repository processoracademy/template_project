module cdc_level_synchronizer #(
    parameter integer CHAIN_DEPTH = 4,
    parameter integer CONFIRMATION_DEPTH = 2
)(
    input                      input_clk_i,
    input                      async_rst_i,
    input                      data_i,

    input  common_p::clk_dom_s output_dom_i,
    output               logic data_o
);

/*
After the chain output signal goes high for `CONFIRMATION_DEPTH` cycles, the syncronizer chain will toggle high.
After the chain output signal goes low for `CONFIRMATION_DEPTH` cycles, the syncronizer chain will toggle low.
*/
// Input Domain
    reg input_current;
    always_ff @(posedge input_clk_i or posedge async_rst_i) begin
        if (async_rst) begin
            input_current <= 1'b0;
        end
        else begin
            input_current <= data_i;
        end
    end

// Output Domain
    wire clk = output_dom_i.clk;
    wire clk_en = output_dom_i.clk_en;
    wire sync_rst = output_dom_i.sync_rst;

    localparam FINAL_DEPTH = CHAIN_DEPTH + CONFIRMATION_DEPTH;
    logic [FINAL_DEPTH-1:0] sync_chain_vec_current;
    genvar i;
    generate
        for (i = 0; i < FINAL_DEPTH; i = i + 1) begin : chain_gen
            always_ff @(posedge clk or posedge async_rst_i) begin
                if (async_rst) begin
                    sync_chain_vec_current[i] <= 1'b0;
                end
                else begin
                    sync_chain_vec_current[i] <= (i == 0)
                                               ? input_current
                                               : sync_chain_vec_current[i-1];
                end
            end
        end
    endgenerate

    wire                   rising_edge_check = &sync_chain_vec_current[FINAL_DEPTH-1:CHAIN_DEPTH];
    wire [FINAL_DEPTH-1:0] inverted_chain = ~sync_chain_vec_current;
    wire                   falling_edge_check = &inverted_chain[FINAL_DEPTH-1:CHAIN_DEPTH];

    // Note: This register does not need an async rst, the falling edge detection will drop automatically on the next cycle.
    wire data_o_next = ~sync_rst && rising_edge_check;
    wire data_o_trigger = sync_rst
                       || (clk_en && rising_edge_check)
                       || (clk_en && falling_edge_check);
    always_ff @(posedge clk) begin
        if (data_o_trigger) begin
            data_o <= data_o_next;
        end
    end

endmodule : cdc_level_synchronizer
