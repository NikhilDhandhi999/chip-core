// rtl/argmax_unit.v
// Hardware 4-Class Argmax Decision Engine

module argmax_unit (
    input  wire signed [31:0] logit0,
    input  wire signed [31:0] logit1,
    input  wire signed [31:0] logit2,
    input  wire signed [31:0] logit3,
    output reg         [1:0]  best_class,
    output reg  signed [31:0] best_score
);

    reg        [1:0]  win_01;
    reg signed [31:0] max_01;
    reg        [1:0]  win_23;
    reg signed [31:0] max_23;

    always @(*) begin
        if (logit1 > logit0) begin
            win_01 = 2'd1;
            max_01 = logit1;
        end else begin
            win_01 = 2'd0;
            max_01 = logit0;
        end

        if (logit3 > logit2) begin
            win_23 = 2'd3;
            max_23 = logit3;
        end else begin
            win_23 = 2'd2;
            max_23 = logit2;
        end

        if (max_23 > max_01) begin
            best_class = win_23;
            best_score = max_23;
        end else begin
            best_class = win_01;
            best_score = max_01;
        end
    end

endmodule
