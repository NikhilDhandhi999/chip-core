// rtl/mac_pe.v
// Dual-Mode Zero-Skipping Processing Element (Synthesizable RTL)
//   - Mode 0 (Standard INT8): accumulator <= accumulator + (activation * weight)
//   - Mode 1 (1.58-Bit Ternary {-1, 0, +1}):
//       Bypasses the hardware multiplier completely!
//       weight == +1 -> accumulator + activation
//       weight == -1 -> accumulator - activation
//       weight ==  0 -> skipped (zero dynamic switching power)

module mac_pe (
    input  wire               clk,
    input  wire               rst,
    input  wire               clear_acc,
    input  wire               enable,
    input  wire               ternary_mode,
    input  wire signed [7:0]  activation,
    input  wire signed [7:0]  weight,
    output reg  signed [7:0]  act_out,
    output reg  signed [7:0]  wgt_out,
    output reg  signed [31:0] accumulator,
    output wire               skipped,
    output wire               mult_bypassed
);

    assign skipped = enable && ((activation == 8'sd0) || (weight == 8'sd0));
    assign mult_bypassed = enable && !skipped && ternary_mode;
    wire signed [31:0] act_ext = {{24{activation[7]}}, activation};

    always @(posedge clk) begin
        if (rst || clear_acc) begin
            act_out     <= 8'sd0;
            wgt_out     <= 8'sd0;
            accumulator <= 32'sd0;
        end else if (enable) begin
            act_out <= activation;
            wgt_out <= weight;

            if (!skipped) begin
                if (ternary_mode) begin
                    if (weight == 8'sd1) begin
                        accumulator <= accumulator + act_ext;
                    end else if (weight == -8'sd1) begin
                        accumulator <= accumulator - act_ext;
                    end else begin
                        accumulator <= accumulator + (activation * weight);
                    end
                end else begin
                    accumulator <= accumulator + (activation * weight);
                end
            end
        end
    end

endmodule
