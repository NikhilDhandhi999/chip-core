// rtl/ai_chip_synth_top.v
// Unified Programmable AI Processor SoC Core (chip-core v7.0)
// Pure Synthesizable RTL — Zero simulation-only constructs.

module ai_chip_synth_top (
    input  wire                clk,
    input  wire                rst,
    input  wire                start,

    input  wire                inst_wr_en,
    input  wire        [4:0]   inst_wr_addr,
    input  wire        [31:0]  inst_wr_data,

    input  wire                mem_wr_en,
    input  wire        [7:0]   mem_wr_addr,
    input  wire signed [7:0]   mem_wr_data,

    output reg                 done,
    output reg         [4:0]   pc,
    output reg         [7:0]   instructions_retired,
    output reg         [15:0]  total_cycles,
    output reg         [15:0]  total_zero_skips,
    output reg         [15:0]  total_mult_bypasses,

    output reg         [7:0]   pred_classes_flat,
    output reg  signed [127:0] result_int8_flat,
    output reg  signed [511:0] result_int32_flat
);

    localparam OP_NOP       = 4'h0;
    localparam OP_CLEAR_ACC = 4'h1;
    localparam OP_MATMUL    = 4'h2;
    localparam OP_RELU      = 4'h3;
    localparam OP_SOFTERMAX = 4'h4;
    localparam OP_STORE_ACC = 4'h5;
    localparam OP_ARGMAX    = 4'h6;
    localparam OP_HALT      = 4'hF;

    reg        [31:0] inst_mem    [0:31];
    reg signed [7:0]  tensor_sram [0:255];

    always @(posedge clk) begin
        if (inst_wr_en) begin
            inst_mem[inst_wr_addr] <= inst_wr_data;
        end
        if (mem_wr_en) begin
            tensor_sram[mem_wr_addr] <= mem_wr_data;
        end
    end

    reg  [31:0] ir;
    wire [3:0]  dec_opcode;
    wire [3:0]  dec_dst_slot;
    wire [3:0]  dec_src_a;
    wire [3:0]  dec_src_b;
    wire        dec_acc_keep;
    wire        dec_transpose_b;
    wire        dec_ternary_mode;
    wire        dec_causal_mask;
    wire [7:0]  dec_imm;

    instruction_decoder u_decoder (
        .inst_word(ir),
        .opcode(dec_opcode),
        .dst_slot(dec_dst_slot),
        .src_a(dec_src_a),
        .src_b(dec_src_b),
        .acc_keep(dec_acc_keep),
        .transpose_b(dec_transpose_b),
        .ternary_mode(dec_ternary_mode),
        .causal_mask(dec_causal_mask),
        .imm(dec_imm)
    );

    localparam STATE_IDLE        = 3'd0;
    localparam STATE_FETCH       = 3'd1;
    localparam STATE_DECODE      = 3'd2;
    localparam STATE_PREP_MATMUL = 3'd3;
    localparam STATE_EXEC_MATMUL = 3'd4;
    localparam STATE_EXEC_SINGLE = 3'd5;
    localparam STATE_HALT        = 3'd6;

    reg [2:0] state;
    reg [3:0] cycle_cnt;
    reg       clear_acc;
    reg       pe_enable;

    reg signed [7:0] act_row [0:3];
    reg signed [7:0] wgt_col [0:3];

    wire signed [31:0] act_rows_flat = {act_row[3], act_row[2], act_row[1], act_row[0]};
    wire signed [31:0] wgt_cols_flat = {wgt_col[3], wgt_col[2], wgt_col[1], wgt_col[0]};

    wire signed [511:0] acc_flat;
    wire        [15:0]  skip_flags;
    wire        [15:0]  bypass_flags;

    wire [4:0] cycle_skips =
        skip_flags[0]  + skip_flags[1]  + skip_flags[2]  + skip_flags[3]  +
        skip_flags[4]  + skip_flags[5]  + skip_flags[6]  + skip_flags[7]  +
        skip_flags[8]  + skip_flags[9]  + skip_flags[10] + skip_flags[11] +
        skip_flags[12] + skip_flags[13] + skip_flags[14] + skip_flags[15];

    wire [4:0] cycle_bypasses =
        bypass_flags[0]  + bypass_flags[1]  + bypass_flags[2]  + bypass_flags[3]  +
        bypass_flags[4]  + bypass_flags[5]  + bypass_flags[6]  + bypass_flags[7]  +
        bypass_flags[8]  + bypass_flags[9]  + bypass_flags[10] + bypass_flags[11] +
        bypass_flags[12] + bypass_flags[13] + bypass_flags[14] + bypass_flags[15];

    integer r_idx, c_idx, k_a, k_b;
    always @(*) begin
        for (r_idx = 0; r_idx < 4; r_idx = r_idx + 1) begin
            act_row[r_idx] = 8'sd0;
            if (state == STATE_EXEC_MATMUL) begin
                k_a = $signed({1'b0, cycle_cnt}) - r_idx;
                if (k_a >= 0 && k_a < 4) begin
                    act_row[r_idx] = tensor_sram[{dec_src_a, r_idx[1:0], k_a[1:0]}];
                end
            end
        end

        for (c_idx = 0; c_idx < 4; c_idx = c_idx + 1) begin
            wgt_col[c_idx] = 8'sd0;
            if (state == STATE_EXEC_MATMUL) begin
                k_b = $signed({1'b0, cycle_cnt}) - c_idx;
                if (k_b >= 0 && k_b < 4) begin
                    if (dec_transpose_b)
                        wgt_col[c_idx] = tensor_sram[{dec_src_b, c_idx[1:0], k_b[1:0]}];
                    else
                        wgt_col[c_idx] = tensor_sram[{dec_src_b, k_b[1:0], c_idx[1:0]}];
                end
            end
        end
    end

    systolic_array_4x4 u_systolic (
        .clk(clk),
        .rst(rst),
        .clear_acc(clear_acc),
        .enable(pe_enable),
        .ternary_mode(dec_ternary_mode),
        .act_rows_flat(act_rows_flat),
        .wgt_cols_flat(wgt_cols_flat),
        .acc_flat(acc_flat),
        .skip_flags(skip_flags),
        .bypass_flags(bypass_flags)
    );

    wire signed [511:0] relu_int32_flat;
    wire signed [127:0] relu_int8_flat;
    wire signed [127:0] softermax_probs_flat;
    wire signed [127:0] store_int8_flat;
    wire        [7:0]   argmax_classes_wire;

    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_post_ops
            relu_unit u_relu (
                .in_val(acc_flat[g*32 +: 32]),
                .shift_amt(dec_imm[4:0]),
                .relu_int32(relu_int32_flat[g*32 +: 32]),
                .relu_int8(relu_int8_flat[g*8 +: 8])
            );

            wire signed [31:0] raw_val = $signed(acc_flat[g*32 +: 32]);
            wire signed [31:0] sh_val  = raw_val >>> dec_imm[4:0];
            assign store_int8_flat[g*8 +: 8] = (sh_val > 32'sd127)  ?  8'sd127 :
                                               (sh_val < -32'sd128) ? -8'sd128 : sh_val[7:0];
        end
    endgenerate

    genvar r;
    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_row_ops
            softermax_unit u_sm (
                .causal_mask_en(dec_causal_mask),
                .row_idx(r[1:0]),
                .scale_shift(dec_imm[3:0]),
                .s0(acc_flat[(r*4 + 0)*32 +: 32]),
                .s1(acc_flat[(r*4 + 1)*32 +: 32]),
                .s2(acc_flat[(r*4 + 2)*32 +: 32]),
                .s3(acc_flat[(r*4 + 3)*32 +: 32]),
                .p0(softermax_probs_flat[(r*4 + 0)*8 +: 8]),
                .p1(softermax_probs_flat[(r*4 + 1)*8 +: 8]),
                .p2(softermax_probs_flat[(r*4 + 2)*8 +: 8]),
                .p3(softermax_probs_flat[(r*4 + 3)*8 +: 8])
            );

            wire signed [31:0] unused_score;
            argmax_unit u_argmax (
                .logit0(acc_flat[(r*4 + 0)*32 +: 32]),
                .logit1(acc_flat[(r*4 + 1)*32 +: 32]),
                .logit2(acc_flat[(r*4 + 2)*32 +: 32]),
                .logit3(acc_flat[(r*4 + 3)*32 +: 32]),
                .best_class(argmax_classes_wire[r*2 +: 2]),
                .best_score(unused_score)
            );
        end
    endgenerate

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            state                <= STATE_IDLE;
            pc                   <= 5'd0;
            ir                   <= 32'd0;
            cycle_cnt            <= 4'd0;
            clear_acc            <= 1'b0;
            pe_enable            <= 1'b0;
            done                 <= 1'b0;
            instructions_retired <= 8'd0;
            total_cycles         <= 16'd0;
            total_zero_skips     <= 16'd0;
            total_mult_bypasses  <= 16'd0;
            pred_classes_flat    <= 8'd0;
            result_int8_flat     <= 128'd0;
            result_int32_flat    <= 512'd0;
        end else begin
            if (state != STATE_IDLE && state != STATE_HALT) begin
                total_cycles <= total_cycles + 16'd1;
            end

            case (state)
                STATE_IDLE: begin
                    done      <= 1'b0;
                    clear_acc <= 1'b0;
                    pe_enable <= 1'b0;
                    if (start) begin
                        pc                   <= 5'd0;
                        instructions_retired <= 8'd0;
                        total_cycles         <= 16'd0;
                        total_zero_skips     <= 16'd0;
                        total_mult_bypasses  <= 16'd0;
                        state                <= STATE_FETCH;
                    end
                end

                STATE_FETCH: begin
                    ir    <= inst_mem[pc];
                    state <= STATE_DECODE;
                end

                STATE_DECODE: begin
                    case (dec_opcode)
                        OP_NOP: begin
                            pc                   <= pc + 5'd1;
                            instructions_retired <= instructions_retired + 8'd1;
                            state                <= STATE_FETCH;
                        end

                        OP_CLEAR_ACC: begin
                            clear_acc <= 1'b1;
                            state     <= STATE_EXEC_SINGLE;
                        end

                        OP_MATMUL: begin
                            if (!dec_acc_keep) begin
                                clear_acc <= 1'b1;
                                state     <= STATE_PREP_MATMUL;
                            end else begin
                                cycle_cnt <= 4'd0;
                                pe_enable <= 1'b1;
                                state     <= STATE_EXEC_MATMUL;
                            end
                        end

                        OP_RELU, OP_SOFTERMAX, OP_STORE_ACC, OP_ARGMAX: begin
                            state <= STATE_EXEC_SINGLE;
                        end

                        OP_HALT: begin
                            instructions_retired <= instructions_retired + 8'd1;
                            done                 <= 1'b1;
                            state                <= STATE_HALT;
                        end

                        default: begin
                            done  <= 1'b1;
                            state <= STATE_HALT;
                        end
                    endcase
                end

                STATE_PREP_MATMUL: begin
                    clear_acc <= 1'b0;
                    cycle_cnt <= 4'd0;
                    pe_enable <= 1'b1;
                    state     <= STATE_EXEC_MATMUL;
                end

                STATE_EXEC_MATMUL: begin
                    total_zero_skips    <= total_zero_skips + {11'd0, cycle_skips};
                    total_mult_bypasses <= total_mult_bypasses + {11'd0, cycle_bypasses};

                    if (cycle_cnt == 4'd9) begin
                        pe_enable            <= 1'b0;
                        pc                   <= pc + 5'd1;
                        instructions_retired <= instructions_retired + 8'd1;
                        state                <= STATE_FETCH;
                    end else begin
                        cycle_cnt <= cycle_cnt + 4'd1;
                    end
                end

                STATE_EXEC_SINGLE: begin
                    clear_acc <= 1'b0;

                    case (dec_opcode)
                        OP_RELU: begin
                            for (i = 0; i < 16; i = i + 1) begin
                                tensor_sram[{dec_dst_slot, i[3:0]}] <= relu_int8_flat[i*8 +: 8];
                            end
                            result_int8_flat  <= relu_int8_flat;
                            result_int32_flat <= relu_int32_flat;
                        end

                        OP_SOFTERMAX: begin
                            for (i = 0; i < 16; i = i + 1) begin
                                tensor_sram[{dec_dst_slot, i[3:0]}] <= softermax_probs_flat[i*8 +: 8];
                            end
                            result_int8_flat  <= softermax_probs_flat;
                            result_int32_flat <= acc_flat;
                        end

                        OP_STORE_ACC: begin
                            for (i = 0; i < 16; i = i + 1) begin
                                tensor_sram[{dec_dst_slot, i[3:0]}] <= store_int8_flat[i*8 +: 8];
                            end
                            result_int8_flat  <= store_int8_flat;
                            result_int32_flat <= acc_flat;
                        end

                        OP_ARGMAX: begin
                            pred_classes_flat <= argmax_classes_wire;
                            result_int32_flat <= acc_flat;
                        end

                        default: ;
                    endcase

                    pc                   <= pc + 5'd1;
                    instructions_retired <= instructions_retired + 8'd1;
                    state                <= STATE_FETCH;
                end

                STATE_HALT: begin
                    done <= 1'b1;
                    if (!start) begin
                        state <= STATE_IDLE;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
