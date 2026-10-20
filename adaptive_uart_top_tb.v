`timescale 1ns/1ps

// ============================================================
// Testbench : adaptive_uart_top
//
// 1. Baud rate auto-detection (115200 bps)
// 2. RX path: 10 known bytes, checked against a scoreboard
// 3. TX path: 5 bytes, decoded from the tx line and checked
// 4. Full duplex: RX and TX frames at the same time
// 5. Stress test: 500 pseudo-random bytes through RX
// 6. Sparse traffic (1 byte per ~1 ms): clock-enable activity
// 7. Idle: all three gated clocks must be off
//
// Pass/fail counts are cumulative (total_pass / total_fail) and the
// final status is computed from them, so an early failure cannot be
// hidden by a later phase. Power-mode checks are real assertions.
// ============================================================
module adaptive_uart_top_tb;

localparam CLK_FREQ   = 50_000_000;
localparam CLK_PERIOD = 20;
localparam BAUD       = 115200;
localparam BIT_NS     = 1_000_000_000 / BAUD;     // 8680 ns

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

// ------------------------------------------------------------
// Counters. total_* never reset; phase_* are reset per phase.
// ------------------------------------------------------------
integer total_pass = 0;
integer total_fail = 0;
integer phase_pass = 0;
integer phase_fail = 0;

task record;
    input ok;
    begin
        if (ok) begin total_pass = total_pass + 1; phase_pass = phase_pass + 1; end
        else    begin total_fail = total_fail + 1; phase_fail = phase_fail + 1; end
    end
endtask

// ------------------------------------------------------------
// RX scoreboard (expected bytes are queued by rx_send_byte)
// ------------------------------------------------------------
reg [7:0] expect_q [0:511];
integer   eq_wr = 0;
integer   eq_rd = 0;

// While high, frames seen by the receiver are counted but not scored.
// Used right after baud lock (see TEST 1).
reg       ignore_rx    = 0;
integer   ignored_rx_n = 0;
reg [7:0] ignored_rx_last;

always @(posedge clk) begin
    if (rx_valid) begin
        if (ignore_rx) begin
            ignored_rx_n    = ignored_rx_n + 1;
            ignored_rx_last = rx_data;
        end else begin
            if (rx_data === expect_q[eq_rd % 512]) record(1);
            else begin
                $display("FAIL: Expected 0x%h | Got 0x%h",
                          expect_q[eq_rd % 512], rx_data);
                record(0);
            end
            eq_rd = eq_rd + 1;
        end
    end
end

// ------------------------------------------------------------
// TX monitor: decodes frames on the tx line (8N1 at BAUD)
// ------------------------------------------------------------
reg [7:0] txq [0:63];
reg       txq_stop_ok [0:63];
integer   tx_wr = 0;
integer   tx_rd = 0;

always @(negedge tx) begin : tx_monitor
    integer k;
    reg [7:0] b;
    #(BIT_NS/2);
    if (tx === 1'b0) begin                  // valid start bit
        for (k = 0; k < 8; k = k + 1) begin
            #(BIT_NS);
            b[k] = tx;
        end
        #(BIT_NS);
        txq[tx_wr % 64]         = b;
        txq_stop_ok[tx_wr % 64] = (tx === 1'b1);
        tx_wr = tx_wr + 1;
    end
end

// ------------------------------------------------------------
// Clock-enable activity (cycles each gated clock is enabled)
// ------------------------------------------------------------
integer act_total = 0, act_tx = 0, act_rx = 0, act_baud = 0;
reg     act_en = 0;
real    duty;

always @(posedge clk) begin
    if (act_en) begin
        act_total = act_total + 1;
        if (clk_tx_active)   act_tx   = act_tx   + 1;
        if (clk_rx_active)   act_rx   = act_rx   + 1;
        if (clk_baud_active) act_baud = act_baud + 1;
    end
end

// ------------------------------------------------------------
// Tasks
// ------------------------------------------------------------

// Baud-detect stimulus: a single low pulse one bit wide.
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
        if (eq_rd < eq_wr) begin
            $display("FAIL: timeout waiting for rx_valid (sent 0x%h)", data);
            record(0);
            eq_rd = eq_wr;      // resynchronise the scoreboard
        end
    end
endtask

// Sends one byte and checks the frame decoded from the tx line.
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
        repeat(CLK_FREQ/BAUD * 12) @(posedge clk);

        if (tx_rd >= tx_wr) begin
            $display("FAIL: no frame seen on tx (sent 0x%h)", data);
            record(0);
        end else begin
            if (txq[tx_rd % 64] === data && txq_stop_ok[tx_rd % 64]) begin
                $display("PASS: TX sent 0x%h | line decoded 0x%h", data, txq[tx_rd % 64]);
                record(1);
            end else begin
                $display("FAIL: TX sent 0x%h | line decoded 0x%h (stop ok=%b)",
                          data, txq[tx_rd % 64], txq_stop_ok[tx_rd % 64]);
                record(0);
            end
            tx_rd = tx_rd + 1;
        end
    end
endtask

// Prints the clock-enable state and checks it against the expected mode
// (1 = clock must be running, 0 = clock must be gated).
task check_power;
    input [8*64:1] mode_name;
    input          exp_tx, exp_rx, exp_baud;
    begin
        $display("\n[POWER] Mode: %0s", mode_name);
        $display("  clk_tx   : %s", clk_tx_active   ? "RUNNING" : "GATED");
        $display("  clk_rx   : %s", clk_rx_active   ? "RUNNING" : "GATED");
        $display("  clk_baud : %s", clk_baud_active ? "RUNNING" : "GATED");
        if (clk_tx_active   === exp_tx)   record(1);
        else begin $display("FAIL: clk_tx expected %s",   exp_tx   ? "RUNNING" : "GATED"); record(0); end
        if (clk_rx_active   === exp_rx)   record(1);
        else begin $display("FAIL: clk_rx expected %s",   exp_rx   ? "RUNNING" : "GATED"); record(0); end
        if (clk_baud_active === exp_baud) record(1);
        else begin $display("FAIL: clk_baud expected %s", exp_baud ? "RUNNING" : "GATED"); record(0); end
    end
endtask

// Restart / print the clock-enable activity counters for one workload phase.
task activity_start;
    begin
        act_total = 0; act_tx = 0; act_rx = 0; act_baud = 0;
        act_en = 1;
    end
endtask

task activity_report;
    input [8*64:1] label;
    begin
        act_en = 0;
        $display("\n[ACTIVITY] %0s  (%0d cycles; ungated reference = 100%% each)", label, act_total);
        duty = (100.0 * act_tx)   / act_total;
        $display("  clk_tx   enabled %6.2f %%", duty);
        duty = (100.0 * act_rx)   / act_total;
        $display("  clk_rx   enabled %6.2f %%", duty);
        duty = (100.0 * act_baud) / act_total;
        $display("  clk_baud enabled %6.2f %%", duty);
    end
endtask

// ------------------------------------------------------------
// LFSR for the stress test
// ------------------------------------------------------------
reg [7:0] lfsr;
function [7:0] next_rand;
    input [7:0] prev;
    begin
        next_rand = {prev[6:0], prev[7]^prev[5]^prev[4]^prev[3]};
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
    lfsr       = 8'hAC;

    repeat(20) @(posedge clk);
    rst = 0;
    repeat(20) @(posedge clk);

    // ---- TEST 1: Baud detection ---------------------------------
    $display("============================================");
    $display("  TEST 1: Baud Rate Auto-Detection");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;

    // The lone low pulse used to trigger detection looks like a start bit
    // followed by eight 1s and a stop bit, so the (running) receiver also
    // decodes it as a 0xFF frame about 10 bit-times later. That frame is a
    // stimulus artifact, not a received byte: wait for it, count it, and
    // keep it out of the scoreboard.
    ignore_rx = 1;
    send_start_bit(BAUD);

    if (baud_locked) begin
        $display("PASS: Baud locked - div=%0d index=%0d", baud_div, baud_index);
        record(1);
    end else begin
        $display("FAIL: Baud not locked");
        record(0);
    end
    if (baud_div == 434) record(1);
    else begin $display("FAIL: expected baud_div=434, got %0d", baud_div); record(0); end

    #(BIT_NS * 12);
    ignore_rx = 0;
    $display("NOTE: receiver decoded %0d frame(s) from the baud-lock pulse (last=0x%h); ignored",
              ignored_rx_n, ignored_rx_last);
    eq_rd = eq_wr;

    // ---- TEST 2: RX 10 known bytes ------------------------------
    $display("\n============================================");
    $display("  TEST 2: RX Path - 10 Known Bytes");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;

    fork
        begin
            rx_send_byte(8'h55, BAUD);
        end
        begin
            #(BIT_NS * 5);
            check_power("RX ACTIVE (mid-frame)", 0, 1, 0);
        end
    join
    rx_send_byte(8'hAA, BAUD);
    rx_send_byte(8'h00, BAUD);
    rx_send_byte(8'hFF, BAUD);
    rx_send_byte(8'h41, BAUD);
    rx_send_byte(8'h42, BAUD);
    rx_send_byte(8'h43, BAUD);
    rx_send_byte(8'hA3, BAUD);
    rx_send_byte(8'h7F, BAUD);
    rx_send_byte(8'h2D, BAUD);

    $display("RX Known Bytes + power check: %0d PASS | %0d FAIL", phase_pass, phase_fail);

    // ---- TEST 3: TX 5 bytes -------------------------------------
    $display("\n============================================");
    $display("  TEST 3: TX Path - 5 Bytes");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;

    // Let the RX hold timer expire so RX is gated while only TX runs.
    repeat(3000) @(posedge clk);

    fork
        begin
            tx_send_byte(8'h55);
        end
        begin
            #(BIT_NS * 5);
            check_power("TX ACTIVE (mid-frame)", 1, 0, 0);
        end
    join
    tx_send_byte(8'hAA);
    tx_send_byte(8'hFF);
    tx_send_byte(8'h41);
    tx_send_byte(8'h2D);

    $display("TX Known Bytes + power check: %0d PASS | %0d FAIL", phase_pass, phase_fail);

    // ---- TEST 4: Full duplex ------------------------------------
    $display("\n============================================");
    $display("  TEST 4: Full Duplex (RX and TX frames together)");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;

    repeat(3000) @(posedge clk);

    fork
        begin
            rx_send_byte(8'h3C, BAUD);
        end
        begin
            tx_send_byte(8'hC3);
        end
        begin
            #(BIT_NS * 5);
            check_power("FULL DUPLEX (mid-frame)", 1, 1, 0);
        end
    join

    $display("Full duplex: %0d PASS | %0d FAIL", phase_pass, phase_fail);

    // ---- TEST 5: 500 random bytes -------------------------------
    $display("\n============================================");
    $display("  TEST 5: 500 Random Bytes Stress Test");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;
    activity_start;

    for (i = 0; i < 500; i = i + 1) begin
        lfsr      = next_rand(lfsr);
        rand_byte = lfsr;
        rx_send_byte(rand_byte, BAUD);
        if ((i+1) % 100 == 0)
            $display("Progress: %0d/500 | PASS:%0d FAIL:%0d",
                      i+1, phase_pass, phase_fail);
    end

    $display("\nStress Test: %0d PASS | %0d FAIL", phase_pass, phase_fail);
    activity_report("Back-to-back RX traffic (worst case for RX gating)");

    // ---- TEST 6: Sparse traffic ---------------------------------
    $display("\n============================================");
    $display("  TEST 6: Sparse Traffic - 20 bytes, ~1 ms apart");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;
    activity_start;

    for (i = 0; i < 20; i = i + 1) begin
        lfsr      = next_rand(lfsr);
        rand_byte = lfsr;
        rx_send_byte(rand_byte, BAUD);
        #1_000_000;                             // 1 ms of idle line
    end

    $display("Sparse traffic: %0d PASS | %0d FAIL", phase_pass, phase_fail);
    activity_report("Sparse RX traffic (typical IoT sensor workload)");

    // ---- TEST 7: Idle -------------------------------------------
    $display("\n============================================");
    $display("  TEST 7: Idle - all clocks must be gated");
    $display("============================================");
    phase_pass = 0; phase_fail = 0;

    rx_drive = 1'b1;
    repeat(10000) @(posedge clk);
    check_power("IDLE (post-lock, after hold timer)", 0, 0, 0);

    // ---- FINAL --------------------------------------------------
    $display("\n============================================");
    $display("  ADAPTIVE UART - FINAL RESULTS");
    $display("  Baud Detection : %s", baud_locked ? "LOCKED" : "FAILED");
    $display("  Total checks   : %0d PASS | %0d FAIL", total_pass, total_fail);
    $display("  Status         : %s",
              (total_fail == 0 && baud_locked) ? "ALL TESTS PASSED" : "FAILURES");
    $display("============================================");

    $finish;
end

initial begin
    $dumpfile("adaptive_uart_top.vcd");
    $dumpvars(0, adaptive_uart_top_tb);
end

endmodule
