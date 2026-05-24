`timescale 1ns/1ps

module adaptive_uart_top_tb;

localparam CLK_FREQ   = 50_000_000;
localparam CLK_PERIOD = 20;

reg         clk, rst;
reg  [7:0]  tx_data;
reg         tx_start;
wire        tx, tx_busy;
reg         rx_drive;
wire [7:0]  rx_data;
wire        rx_valid, rx_error;
wire        baud_locked;
wire [2:0]  baud_index;
wire [15:0] baud_div;
wire        clk_tx_active;
wire        clk_rx_active;
wire        clk_baud_active;

adaptive_uart_top #(.CLK_FREQ(CLK_FREQ)) DUT (
    .clk            (clk),
    .rst            (rst),
    .tx_data        (tx_data),
    .tx_start       (tx_start),
    .tx             (tx),
    .tx_busy        (tx_busy),
    .rx             (rx_drive),
    .rx_data        (rx_data),
    .rx_valid       (rx_valid),
    .rx_error       (rx_error),
    .baud_locked    (baud_locked),
    .baud_index     (baud_index),
    .baud_div       (baud_div),
    .clk_tx_active  (clk_tx_active),
    .clk_rx_active  (clk_rx_active),
    .clk_baud_active(clk_baud_active)
);

always #(CLK_PERIOD/2) clk = ~clk;

// ?? scoreboard with queue ?????????????????????????????????????
integer pass_count;
integer fail_count;
reg [7:0] expect_q [0:511];
integer   eq_wr;
integer   eq_rd;

always @(posedge clk) begin
    if (rx_valid) begin
        if (rx_data === expect_q[eq_rd % 512]) begin
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL: Expected 0x%h | Got 0x%h",
                      expect_q[eq_rd % 512], rx_data);
            fail_count = fail_count + 1;
        end
        eq_rd = eq_rd + 1;
    end
end

// ?? baud detect task ??????????????????????????????????????????
task send_start_bit;
    input integer baud_rate;
    integer baud_period_ns;
    begin
        baud_period_ns = 1_000_000_000 / baud_rate;
        rx_drive = 1'b1;
        #(baud_period_ns * 2);
        rx_drive = 1'b0;
        #(baud_period_ns);
        rx_drive = 1'b1;
        #(CLK_PERIOD * 50);
    end
endtask

// ?? RX send task ??????????????????????????????????????????????
task rx_send_byte;
    input [7:0]  data;
    input integer baud_rate;
    integer baud_period_ns;
    integer i, timeout;
    begin
        baud_period_ns = 1_000_000_000 / baud_rate;

        expect_q[eq_wr % 512] = data;
        eq_wr = eq_wr + 1;

        // start bit
        rx_drive = 1'b0;
        #(baud_period_ns);

        // 8 data bits LSB first
        for (i = 0; i < 8; i = i + 1) begin
            rx_drive = data[i];
            #(baud_period_ns);
        end

        // stop bit + margin
        rx_drive = 1'b1;
        #(baud_period_ns * 2);

        // poll until byte received
        timeout = 0;
        while (eq_rd < eq_wr && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
    end
endtask

// ?? TX send task ??????????????????????????????????????????????
task tx_send_byte;
    input [7:0] data;
    integer timeout;
    begin
        timeout = 0;
        while (tx_busy && timeout < 100000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        @(negedge clk);
        tx_data  = data;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;
        repeat(CLK_FREQ/115200 * 12) @(posedge clk);
    end
endtask

// ?? power report task ?????????????????????????????????????????
task report_power_mode;
    input [255:0] mode_name;
    begin
        $display("\n[POWER] Mode: %s", mode_name);
        $display("  clk_tx   : %s",
                  clk_tx_active   ? "RUNNING" : "GATED");
        $display("  clk_rx   : %s",
                  clk_rx_active   ? "RUNNING" : "GATED");
        $display("  clk_baud : %s",
                  clk_baud_active ? "RUNNING" : "GATED");
    end
endtask

// ?? LFSR ??????????????????????????????????????????????????????
reg [7:0] lfsr;
function [7:0] next_rand;
    input [7:0] prev;
    begin
        next_rand = {prev[6:0],
                     prev[7]^prev[5]^prev[4]^prev[3]};
    end
endfunction

integer i;
reg [7:0] rand_byte;

initial begin
    clk        = 0;
    rst        = 1;
    tx_data    = 0;
    tx_start   = 0;
    rx_drive   = 1'b1;
    pass_count = 0;
    fail_count = 0;
    eq_wr      = 0;
    eq_rd      = 0;
    lfsr       = 8'hAC;

    repeat(20) @(posedge clk);
    rst = 0;
    repeat(20) @(posedge clk);

    // ?? TEST 1: Baud detection ????????????????????????????????
    $display("============================================");
    $display("  TEST 1: Baud Rate Auto-Detection");
    $display("============================================");

    send_start_bit(115200);

    if (baud_locked)
        $display("PASS: Baud locked ? div=%0d index=%0d",
                  baud_div, baud_index);
    else
        $display("FAIL: Baud not locked");

    report_power_mode("POST-LOCK IDLE");

    // ?? TEST 2: RX 10 known bytes ?????????????????????????????
    $display("\n============================================");
    $display("  TEST 2: RX Path ? 10 Known Bytes");
    $display("============================================");

    report_power_mode("RX ACTIVE");

    rx_send_byte(8'h55, 115200);
    rx_send_byte(8'hAA, 115200);
    rx_send_byte(8'h00, 115200);
    rx_send_byte(8'hFF, 115200);
    rx_send_byte(8'h41, 115200);
    rx_send_byte(8'h42, 115200);
    rx_send_byte(8'h43, 115200);
    rx_send_byte(8'hA3, 115200);
    rx_send_byte(8'h7F, 115200);
    rx_send_byte(8'h2D, 115200);

    $display("RX Known Bytes: %0d PASS | %0d FAIL",
              pass_count, fail_count);

    // ?? TEST 3: TX 5 bytes ????????????????????????????????????
    $display("\n============================================");
    $display("  TEST 3: TX Path ? 5 Bytes");
    $display("============================================");

    report_power_mode("TX ACTIVE");

    tx_send_byte(8'h55);
    tx_send_byte(8'hAA);
    tx_send_byte(8'hFF);
    tx_send_byte(8'h41);
    tx_send_byte(8'h2D);
    $display("TX: 5 bytes transmitted");

    // ?? TEST 4: 500 random bytes ??????????????????????????????
    $display("\n============================================");
    $display("  TEST 4: 500 Random Bytes Stress Test");
    $display("============================================");

    pass_count = 0;
    fail_count = 0;
    eq_wr      = 0;
    eq_rd      = 0;

    for (i = 0; i < 500; i = i + 1) begin
        lfsr      = next_rand(lfsr);
        rand_byte = lfsr;
        rx_send_byte(rand_byte, 115200);
        if ((i+1) % 100 == 0)
            $display("Progress: %0d/500 | PASS:%0d FAIL:%0d",
                      i+1, pass_count, fail_count);
    end

    $display("\nStress Test: %0d PASS | %0d FAIL",
              pass_count, fail_count);

    // ?? TEST 5: Power modes ???????????????????????????????????
    $display("\n============================================");
    $display("  TEST 5: Power Mode Transitions");
    $display("============================================");

    rx_drive = 1'b1;
    repeat(500) @(posedge clk);
    report_power_mode("IDLE ? all should be gated");

    // ?? FINAL ?????????????????????????????????????????????????
    $display("\n============================================");
    $display("  ADAPTIVE UART ? FINAL RESULTS");
    $display("  Baud Detection : %s",
              baud_locked ? "LOCKED" : "FAILED");
    $display("  Stress Test    : %0d PASS | %0d FAIL",
              pass_count, fail_count);
    $display("  Status         : %s",
              fail_count==0 ? "ALL TESTS PASSED":"FAILURES");
    $display("============================================");

    $finish;
end

initial begin
    $dumpfile("adaptive_uart_top.vcd");
    $dumpvars(0, adaptive_uart_top_tb);
end

endmodule