// rtl/instruction_decoder.v
// 32-Bit Tensor ISA Instruction Decoder for chip-core (v7.2)

module instruction_decoder (
    input  wire [31:0] inst_word,
    output wire [3:0]  opcode,
    output wire [3:0]  dst_slot,
    output wire [3:0]  src_a,
    output wire [3:0]  src_b,
    output wire        acc_keep,
    output wire        transpose_b,
    output wire        ternary_mode,
    output wire        causal_mask,
    output wire [7:0]  imm
);

    assign opcode       = inst_word[31:28];
    assign dst_slot     = inst_word[27:24];
    assign src_a        = inst_word[23:20];
    assign src_b        = inst_word[19:16];
    assign acc_keep     = inst_word[8];
    assign transpose_b  = inst_word[9];
    assign ternary_mode = inst_word[10];
    assign causal_mask  = inst_word[11];
    assign imm          = inst_word[7:0];

endmodule
