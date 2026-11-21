// tb/tb_ai_chip_top.v
// Dual-Workload End-to-End UART Serial Host Bridge Testbench (chip-core v7.2)

`timescale 1ns/1ps

module tb_ai_chip_top;

    localparam integer CLKS_PER_BIT = 4;
    localparam integer BIT_PERIOD   = CLKS_PER_BIT * 10;

    reg                 clk;
    reg                 rst;
    reg                 rx_serial;
    wire                tx_serial;
    wire                tx_busy;
    wire                core_done;
    wire        [4:0]   pc;
    wire        [7:0]   instructions_retired;
    wire        [15:0]  total_cycles;
    wire        [15:0]  total_zero_skips;
    wire        [15:0]  total_mult_bypasses;
    wire        [7:0]   pred_classes_flat;
    wire signed [127:0] result_int8_flat;
    wire signed [511:0] result_int32_flat;

    reg [7:0] stream_buf [0:4095];
    reg [7:0] gold_attn  [0:15];
    integer   stream_len;
    integer   gold_file, telem_file, r_status;
    integer   g_pred [0:3];
    integer   i, r_i, c_i, b_idx;
    reg [7:0] rx_back_byte;
    reg [7:0] uart_preds [0:3];
    reg signed [7:0] got_val, exp_val;

    reg        attn_match;
    reg [15:0] attn_cycles, attn_skips, attn_bypasses;

    reg        vis_match;
    reg [15:0] vis_cycles, vis_skips, vis_bypasses;

    ai_chip_top #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk(clk),
        .rst(rst),
        .rx_serial(rx_serial),
        .tx_serial(tx_serial),
        .tx_busy(tx_busy),
        .core_done(core_done),
        .pc(pc),
        .instructions_retired(instructions_retired),
        .total_cycles(total_cycles),
        .total_zero_skips(total_zero_skips),
        .total_mult_bypasses(total_mult_bypasses),
        .pred_classes_flat(pred_classes_flat),
        .result_int8_flat(result_int8_flat),
        .result_int32_flat(result_int32_flat)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task uart_send_byte;
        input [7:0] data_b;
        integer k;
        begin
            rx_serial = 1'b0;
            #(BIT_PERIOD);
            for (k = 0; k < 8; k = k + 1) begin
                rx_serial = data_b[k];
                #(BIT_PERIOD);
            end
            rx_serial = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    task uart_recv_byte;
        output [7:0] out_b;
        integer k;
        reg [7:0] acc_b;
        begin
            acc_b = 8'd0;
            @(negedge tx_serial);
            #(BIT_PERIOD + (BIT_PERIOD / 2));
            for (k = 0; k < 8; k = k + 1) begin
                acc_b[k] = tx_serial;
                #(BIT_PERIOD);
            end
            out_b = acc_b;
        end
    endtask

    task stream_and_execute;
        input integer max_idx;
        begin
            for (b_idx = 0; b_idx < max_idx; b_idx = b_idx + 1) begin
                uart_send_byte(stream_buf[b_idx]);
                if (stream_buf[b_idx] == 8'h01) begin
                    for (i = 1; i <= 5; i = i + 1) begin
                        b_idx = b_idx + 1;
                        uart_send_byte(stream_buf[b_idx]);
                    end
                    uart_recv_byte(rx_back_byte);
                    if (rx_back_byte !== 8'h06) begin
                        $display("ERROR: Expected ACK 0x06 after WRITE_INST, got %h", rx_back_byte);
                        $finish;
                    end
                end else if (stream_buf[b_idx] == 8'h02) begin
                    for (i = 1; i <= 2; i = i + 1) begin
                        b_idx = b_idx + 1;
                        uart_send_byte(stream_buf[b_idx]);
                    end
                    uart_recv_byte(rx_back_byte);
                    if (rx_back_byte !== 8'h06) begin
                        $display("ERROR: Expected ACK 0x06 after WRITE_SRAM, got %h", rx_back_byte);
                        $finish;
                    end
                end else if (stream_buf[b_idx] == 8'h03) begin
                    uart_recv_byte(rx_back_byte);
                    if (rx_back_byte !== 8'hAA) begin
                        $display("ERROR: Expected EXEC_DONE 0xAA, got %h", rx_back_byte);
                        $finish;
                    end
                end
            end
        end
    endtask

    task print_class_label;
        input [1:0] cls_id;
        begin
            case (cls_id)
                2'd0: $write("Digit '0'");
                2'd1: $write("Digit '1'");
                2'd2: $write("Symbol 'X'");
                2'd3: $write("Symbol '+'");
            endcase
        end
    endtask

    initial begin
        $dumpfile("build/chip_core.vcd");
        $dumpvars(0, tb_ai_chip_top);

        $readmemh("build/gold_attn.hex", gold_attn);
        stream_len = $fread(stream_buf, $fopen("build/uart_attn_stream.bin", "rb"));

        rst = 1'b1;
        rx_serial = 1'b1;
        #(BIT_PERIOD * 3);
        rst = 1'b0;
        #(BIT_PERIOD * 2);

        stream_and_execute(stream_len);

        attn_cycles   = total_cycles;
        attn_skips    = total_zero_skips;
        attn_bypasses = total_mult_bypasses;
        attn_match    = 1'b1;

        $display("");
        $display("=== [RUN 1] TRANSFORMER SELF-ATTENTION OUTPUT (UART-PROGRAMMED) ===");
        $display("Instructions Retired : %0d | Clock Cycles : %0d | Zero-Skips : %0d",
                 instructions_retired, attn_cycles, attn_skips);
        for (r_i = 0; r_i < 4; r_i = r_i + 1) begin
            $write("  Attn Out Row %0d : [", r_i);
            for (c_i = 0; c_i < 4; c_i = c_i + 1) begin
                got_val = $signed(result_int8_flat[(r_i*4 + c_i)*8 +: 8]);
                exp_val = $signed(gold_attn[r_i*4 + c_i]);
                $write("%5d%s", got_val, (c_i < 3) ? "," : "");
                if (got_val !== exp_val) attn_match = 1'b0;
            end
            $display(" ]");
        end
        $display("RUN 1 STATUS         : %s", attn_match ? "PASS (100% Exact Match)" : "FAIL");

        gold_file = $fopen("build/gold_preds.txt", "r");
        r_status = $fscanf(gold_file, "%d %d %d %d", g_pred[0], g_pred[1], g_pred[2], g_pred[3]);
        $fclose(gold_file);

        stream_len = $fread(stream_buf, $fopen("build/uart_vision_stream.bin", "rb"));
        stream_and_execute(stream_len - 1);

        uart_send_byte(8'h04);
        for (i = 0; i < 4; i = i + 1) begin
            uart_recv_byte(uart_preds[i]);
        end

        vis_cycles   = total_cycles;
        vis_skips    = total_zero_skips;
        vis_bypasses = total_mult_bypasses;
        vis_match    = 1'b1;

        $display("");
        $display("=== [RUN 2] 1.58-BIT TERNARY VISION CLASSIFIER (UART READBACK) ===");
        $display("Instructions Retired : %0d | Clock Cycles : %0d | Zero-Skips : %0d | Ternary Ops : %0d",
                 instructions_retired, vis_cycles, vis_skips, vis_bypasses);
        for (i = 0; i < 4; i = i + 1) begin
            $write("  UART Readback Image %0d -> Class %0d (", i, uart_preds[i][1:0]);
            print_class_label(uart_preds[i][1:0]);
            $display(") | Expected Class %0d", g_pred[i]);
            if (uart_preds[i][1:0] !== g_pred[i][1:0]) vis_match = 1'b0;
        end
        $display("RUN 2 STATUS         : %s", vis_match ? "PASS (100% Exact Match)" : "FAIL");

        telem_file = $fopen("build/sim_telemetry.txt", "w");
        if (telem_file != 0) begin
            $fwrite(telem_file, "%0d %0d %0d %0d %0d %0d %0d %0d\n",
                attn_cycles, attn_skips, attn_bypasses, attn_match ? 1 : 0,
                vis_cycles, vis_skips, vis_bypasses, vis_match ? 1 : 0);
            $fclose(telem_file);
        end

        $display("");
        if (attn_match && vis_match) begin
            $display("OVERALL STATUS: PASS! Both Transformer Attention & Vision Classifier verified.");
        end else begin
            $display("OVERALL STATUS: FAIL!");
        end
        $display("");
        $finish;
    end

endmodule
