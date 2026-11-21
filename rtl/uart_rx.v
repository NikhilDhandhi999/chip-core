// rtl/uart_rx.v
// Synthesizable 8-N-1 UART Receiver (Start bit + 8 Data bits LSB-first + Stop bit)

module uart_rx #(
    parameter integer CLKS_PER_BIT = 4
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_serial,
    output reg  [7:0] rx_byte,
    output reg        rx_valid
);

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shifter;

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            clk_cnt  <= 16'd0;
            bit_idx  <= 3'd0;
            shifter  <= 8'd0;
            rx_byte  <= 8'd0;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_serial == 1'b0) begin
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_cnt == (CLKS_PER_BIT / 2)) begin
                        if (rx_serial == 1'b0) begin
                            clk_cnt <= 16'd0;
                            state   <= S_DATA;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt < (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt          <= 16'd0;
                        shifter[bit_idx] <= rx_serial;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (clk_cnt < (CLKS_PER_BIT - 1)) begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end else begin
                        clk_cnt  <= 16'd0;
                        rx_byte  <= shifter;
                        rx_valid <= 1'b1;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
