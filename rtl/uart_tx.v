// rtl/uart_tx.v
// Synthesizable 8-N-1 UART Transmitter (Start bit=0 + 8 Data bits LSB-first + Stop bit=1)

module uart_tx #(
    parameter integer CLKS_PER_BIT = 4
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_byte,
    output reg        tx_serial,
    output reg        tx_busy
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_reg;

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            data_reg  <= 8'd0;
            tx_serial <= 1'b1;
            tx_busy   <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx_serial <= 1'b1;
                    tx_busy   <= 1'b0;
                    clk_cnt   <= 16'd0;
                    bit_idx   <= 3'd0;
                    if (tx_start) begin
                        data_reg  <= tx_byte;
                        tx_busy   <= 1'b1;
                        tx_serial <= 1'b0;
                        state     <= S_START;
                    end
                end

                S_START: begin
                    tx_serial <= 1'b0;
                    tx_busy   <= 1'b1;
                    if (clk_cnt < (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt   <= 16'd0;
                        bit_idx   <= 3'd0;
                        tx_serial <= data_reg[0];
                        state     <= S_DATA;
                    end
                end

                S_DATA: begin
                    tx_serial <= data_reg[bit_idx];
                    tx_busy   <= 1'b1;
                    if (clk_cnt < (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            bit_idx   <= 3'd0;
                            tx_serial <= 1'b1;
                            state     <= S_STOP;
                        end else begin
                            bit_idx   <= bit_idx + 3'd1;
                            tx_serial <= data_reg[bit_idx + 1];
                        end
                    end
                end

                S_STOP: begin
                    tx_serial <= 1'b1;
                    tx_busy   <= 1'b1;
                    if (clk_cnt < (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt <= 16'd0;
                        tx_busy <= 1'b0;
                        state   <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
