// rtl/uart_host_bridge.v
// UART Host Serial Bridge & Packet Controller for chip-core (v7.0)

module uart_host_bridge #(
    parameter integer CLKS_PER_BIT = 4
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        rx_serial,
    output wire        tx_serial,
    output wire        tx_busy,

    output reg         core_start,
    input  wire        core_done,
    input  wire [7:0]  pred_classes_flat,

    output reg         inst_wr_en,
    output reg  [4:0]  inst_wr_addr,
    output reg  [31:0] inst_wr_data,

    output reg         mem_wr_en,
    output reg  [7:0]  mem_wr_addr,
    output reg  [7:0]  mem_wr_data
);

    wire [7:0] rx_byte;
    wire       rx_valid;

    reg        tx_start;
    reg  [7:0] tx_byte;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk),
        .rst(rst),
        .rx_serial(rx_serial),
        .rx_byte(rx_byte),
        .rx_valid(rx_valid)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_byte(tx_byte),
        .tx_serial(tx_serial),
        .tx_busy(tx_busy)
    );

    localparam CMD_NONE       = 8'h00;
    localparam CMD_WRITE_INST = 8'h01;
    localparam CMD_WRITE_SRAM = 8'h02;
    localparam CMD_RUN_EXEC   = 8'h03;
    localparam CMD_READ_PREDS = 8'h04;

    localparam ST_CMD         = 3'd0;
    localparam ST_PAYLOAD     = 3'd1;
    localparam ST_WAIT_DONE   = 3'd2;
    localparam ST_SEND_REPLY  = 3'd3;

    reg [2:0]  state;
    reg [7:0]  active_cmd;
    reg [2:0]  byte_idx;
    reg [7:0]  buf0, buf1, buf2, buf3, buf4;
    reg [2:0]  reply_cnt;
    reg [7:0]  reply_buf [0:3];
    reg        prev_done;

    always @(posedge clk) begin
        if (rst) begin
            state        <= ST_CMD;
            active_cmd   <= CMD_NONE;
            byte_idx     <= 3'd0;
            buf0         <= 8'd0;
            buf1         <= 8'd0;
            buf2         <= 8'd0;
            buf3         <= 8'd0;
            buf4         <= 8'd0;
            reply_cnt    <= 3'd0;
            reply_buf[0] <= 8'd0;
            reply_buf[1] <= 8'd0;
            reply_buf[2] <= 8'd0;
            reply_buf[3] <= 8'd0;
            prev_done    <= 1'b0;
            core_start   <= 1'b0;
            inst_wr_en   <= 1'b0;
            inst_wr_addr <= 5'd0;
            inst_wr_data <= 32'd0;
            mem_wr_en    <= 1'b0;
            mem_wr_addr  <= 8'd0;
            mem_wr_data  <= 8'd0;
            tx_start     <= 1'b0;
            tx_byte      <= 8'd0;
        end else begin
            inst_wr_en <= 1'b0;
            mem_wr_en  <= 1'b0;
            tx_start   <= 1'b0;
            prev_done  <= core_done;

            case (state)
                ST_CMD: begin
                    if (rx_valid) begin
                        byte_idx <= 3'd0;
                        case (rx_byte)
                            CMD_WRITE_INST: begin
                                active_cmd <= CMD_WRITE_INST;
                                state      <= ST_PAYLOAD;
                            end
                            CMD_WRITE_SRAM: begin
                                active_cmd <= CMD_WRITE_SRAM;
                                state      <= ST_PAYLOAD;
                            end
                            CMD_RUN_EXEC: begin
                                active_cmd <= CMD_RUN_EXEC;
                                core_start <= 1'b1;
                                state      <= ST_WAIT_DONE;
                            end
                            CMD_READ_PREDS: begin
                                active_cmd   <= CMD_READ_PREDS;
                                reply_buf[0] <= {6'd0, pred_classes_flat[1:0]};
                                reply_buf[1] <= {6'd0, pred_classes_flat[3:2]};
                                reply_buf[2] <= {6'd0, pred_classes_flat[5:4]};
                                reply_buf[3] <= {6'd0, pred_classes_flat[7:6]};
                                reply_cnt    <= 3'd0;
                                state        <= ST_SEND_REPLY;
                            end
                            default: begin
                                active_cmd <= CMD_NONE;
                                state      <= ST_CMD;
                            end
                        endcase
                    end
                end

                ST_PAYLOAD: begin
                    if (rx_valid) begin
                        case (byte_idx)
                            3'd0: buf0 <= rx_byte;
                            3'd1: buf1 <= rx_byte;
                            3'd2: buf2 <= rx_byte;
                            3'd3: buf3 <= rx_byte;
                            3'd4: buf4 <= rx_byte;
                            default: ;
                        endcase

                        if (active_cmd == CMD_WRITE_INST && byte_idx == 3'd4) begin
                            inst_wr_en   <= 1'b1;
                            inst_wr_addr <= buf0[4:0];
                            inst_wr_data <= {buf1, buf2, buf3, rx_byte};
                            reply_buf[0] <= 8'h06;
                            reply_cnt    <= 3'd0;
                            state        <= ST_SEND_REPLY;
                        end else if (active_cmd == CMD_WRITE_SRAM && byte_idx == 3'd1) begin
                            mem_wr_en    <= 1'b1;
                            mem_wr_addr  <= buf0;
                            mem_wr_data  <= rx_byte;
                            reply_buf[0] <= 8'h06;
                            reply_cnt    <= 3'd0;
                            state        <= ST_SEND_REPLY;
                        end else begin
                            byte_idx <= byte_idx + 3'd1;
                        end
                    end
                end

                ST_WAIT_DONE: begin
                    if (core_done && !prev_done) begin
                        core_start   <= 1'b0;
                        reply_buf[0] <= 8'hAA;
                        reply_cnt    <= 3'd0;
                        state        <= ST_SEND_REPLY;
                    end
                end

                ST_SEND_REPLY: begin
                    if (!tx_busy && !tx_start) begin
                        tx_byte  <= reply_buf[reply_cnt];
                        tx_start <= 1'b1;
                        if (active_cmd == CMD_READ_PREDS) begin
                            if (reply_cnt == 3'd3) begin
                                state <= ST_CMD;
                            end else begin
                                reply_cnt <= reply_cnt + 3'd1;
                            end
                        end else begin
                            state <= ST_CMD;
                        end
                    end
                end

                default: state <= ST_CMD;
            endcase
        end
    end

endmodule
