// rtl/systolic_array_4x4.v
// 4x4 Output-Stationary Systolic Array (16 Parallel Dual-Mode PEs)

module systolic_array_4x4 (
    input  wire                clk,
    input  wire                rst,
    input  wire                clear_acc,
    input  wire                enable,
    input  wire                ternary_mode,
    input  wire signed [31:0]  act_rows_flat,
    input  wire signed [31:0]  wgt_cols_flat,
    output wire signed [511:0] acc_flat,
    output wire        [15:0]  skip_flags,
    output wire        [15:0]  bypass_flags
);

    wire signed [7:0] act_pipe [0:19];
    wire signed [7:0] wgt_pipe [0:19];

    genvar r, c;
    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_act_in
            assign act_pipe[r*5 + 0] = act_rows_flat[r*8 +: 8];
        end

        for (c = 0; c < 4; c = c + 1) begin : gen_wgt_in
            assign wgt_pipe[0*4 + c] = wgt_cols_flat[c*8 +: 8];
        end

        for (r = 0; r < 4; r = r + 1) begin : gen_row
            for (c = 0; c < 4; c = c + 1) begin : gen_col
                localparam integer IDX = r*4 + c;
                mac_pe u_pe (
                    .clk(clk),
                    .rst(rst),
                    .clear_acc(clear_acc),
                    .enable(enable),
                    .ternary_mode(ternary_mode),
                    .activation(act_pipe[r*5 + c]),
                    .weight(wgt_pipe[r*4 + c]),
                    .act_out(act_pipe[r*5 + (c + 1)]),
                    .wgt_out(wgt_pipe[(r + 1)*4 + c]),
                    .accumulator(acc_flat[IDX*32 +: 32]),
                    .skipped(skip_flags[IDX]),
                    .mult_bypassed(bypass_flags[IDX])
                );
            end
        end
    endgenerate

endmodule
