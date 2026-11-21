// rtl/relu_unit.v
// Hardware ReLU Activation + Fixed-Point Right-Shift Quantizer

module relu_unit (
    input  wire signed [31:0] in_val,
    input  wire        [4:0]  shift_amt,
    output wire signed [31:0] relu_int32,
    output wire signed [7:0]  relu_int8
);

    wire signed [31:0] clamped;
    wire signed [31:0] shifted;

    assign clamped    = (in_val < 32'sd0) ? 32'sd0 : in_val;
    assign shifted    = clamped >>> shift_amt;
    assign relu_int32 = shifted;
    assign relu_int8  = (shifted > 32'sd127) ? 8'sd127 : shifted[7:0];

endmodule
