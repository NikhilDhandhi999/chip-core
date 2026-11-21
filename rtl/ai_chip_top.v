// rtl/ai_chip_top.v
// Top-Level SoC with Integrated UART Serial Host Bridge (chip-core v7.2)

module ai_chip_top #(
    parameter integer CLKS_PER_BIT = 4
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                rx_serial,
    output wire                tx_serial,
    output wire                tx_busy,

    output wire                core_done,
    output wire        [4:0]   pc,
    output wire        [7:0]   instructions_retired,
    output wire        [15:0]  total_cycles,
    output wire        [15:0]  total_zero_skips,
    output wire        [15:0]  total_mult_bypasses,
    output wire        [7:0]   pred_classes_flat,
    output wire signed [127:0] result_int8_flat,
    output wire signed [511:0] result_int32_flat
);

    wire        bridge_start;
    wire        inst_wr_en;
    wire [4:0]  inst_wr_addr;
    wire [31:0] inst_wr_data;
    wire        mem_wr_en;
    wire [7:0]  mem_wr_addr;
    wire signed [7:0] mem_wr_data;

    uart_host_bridge #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_bridge (
        .clk(clk),
        .rst(rst),
        .rx_serial(rx_serial),
        .tx_serial(tx_serial),
        .tx_busy(tx_busy),
        .core_start(bridge_start),
        .core_done(core_done),
        .pred_classes_flat(pred_classes_flat),
        .inst_wr_en(inst_wr_en),
        .inst_wr_addr(inst_wr_addr),
        .inst_wr_data(inst_wr_data),
        .mem_wr_en(mem_wr_en),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data)
    );

    ai_chip_synth_top u_core (
        .clk(clk),
        .rst(rst),
        .start(bridge_start),
        .inst_wr_en(inst_wr_en),
        .inst_wr_addr(inst_wr_addr),
        .inst_wr_data(inst_wr_data),
        .mem_wr_en(mem_wr_en),
        .mem_wr_addr(mem_wr_addr),
        .mem_wr_data(mem_wr_data),
        .done(core_done),
        .pc(pc),
        .instructions_retired(instructions_retired),
        .total_cycles(total_cycles),
        .total_zero_skips(total_zero_skips),
        .total_mult_bypasses(total_mult_bypasses),
        .pred_classes_flat(pred_classes_flat),
        .result_int8_flat(result_int8_flat),
        .result_int32_flat(result_int32_flat)
    );

endmodule
