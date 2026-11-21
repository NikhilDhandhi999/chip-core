// rtl/softermax_unit.v
// Hardware Causal Mask + Integer Base-2 Softmax (Softermax) Row Unit

module softermax_unit (
    input  wire               causal_mask_en,
    input  wire        [1:0]  row_idx,
    input  wire        [3:0]  scale_shift,
    input  wire signed [31:0] s0,
    input  wire signed [31:0] s1,
    input  wire signed [31:0] s2,
    input  wire signed [31:0] s3,
    output reg  signed [7:0]  p0,
    output reg  signed [7:0]  p1,
    output reg  signed [7:0]  p2,
    output reg  signed [7:0]  p3
);

    wire mask0 = 1'b0;
    wire mask1 = causal_mask_en && (2'd1 > row_idx);
    wire mask2 = causal_mask_en && (2'd2 > row_idx);
    wire mask3 = causal_mask_en && (2'd3 > row_idx);

    reg signed [31:0] max_val;
    reg signed [31:0] diff0, diff1, diff2, diff3;
    reg        [31:0] sh0, sh1, sh2, sh3;
    reg        [15:0] u0, u1, u2, u3;
    reg        [15:0] row_sum;
    reg        [31:0] norm0, norm1, norm2, norm3;

    always @(*) begin
        max_val = s0;
        if (!mask1 && (s1 > max_val)) max_val = s1;
        if (!mask2 && (s2 > max_val)) max_val = s2;
        if (!mask3 && (s3 > max_val)) max_val = s3;

        diff0 = max_val - s0;
        diff1 = max_val - s1;
        diff2 = max_val - s2;
        diff3 = max_val - s3;

        sh0 = (diff0 <= 0) ? 32'd0 : (diff0 >> scale_shift);
        sh1 = (diff1 <= 0) ? 32'd0 : (diff1 >> scale_shift);
        sh2 = (diff2 <= 0) ? 32'd0 : (diff2 >> scale_shift);
        sh3 = (diff3 <= 0) ? 32'd0 : (diff3 >> scale_shift);

        u0 = mask0 ? 16'd0 : ((sh0 >= 32'd8) ? 16'd0 : (16'd128 >> sh0[2:0]));
        u1 = mask1 ? 16'd0 : ((sh1 >= 32'd8) ? 16'd0 : (16'd128 >> sh1[2:0]));
        u2 = mask2 ? 16'd0 : ((sh2 >= 32'd8) ? 16'd0 : (16'd128 >> sh2[2:0]));
        u3 = mask3 ? 16'd0 : ((sh3 >= 32'd8) ? 16'd0 : (16'd128 >> sh3[2:0]));

        row_sum = u0 + u1 + u2 + u3;

        norm0 = ({16'd0, u0} * 32'd127) / {16'd0, row_sum};
        norm1 = ({16'd0, u1} * 32'd127) / {16'd0, row_sum};
        norm2 = ({16'd0, u2} * 32'd127) / {16'd0, row_sum};
        norm3 = ({16'd0, u3} * 32'd127) / {16'd0, row_sum};

        p0 = norm0[7:0];
        p1 = norm1[7:0];
        p2 = norm2[7:0];
        p3 = norm3[7:0];
    end

endmodule
