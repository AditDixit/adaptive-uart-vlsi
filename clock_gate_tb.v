`timescale 1ns/1ps

module clock_gate_tb;

localparam CLK_PERIOD = 20;

reg clk, rst;
reg tx_active, rx_active, baud_en;

wire clk_tx, clk_rx, clk_baud;

clock_gate DUT (
    .clk      (clk),
    .rst      (rst),
    .tx_active(tx_active),
    .rx_active(rx_active),
    .baud_en  (baud_en),
    .clk_tx   (clk_tx),
    .clk_rx   (clk_rx),
    .clk_baud (clk_baud)
);

always #(CLK_PERIOD/2) clk = ~clk;

// count toggles on each gated clock
integer tx_toggles   = 0;
integer rx_toggles   = 0;
integer baud_toggles = 0;

always @(posedge clk_tx)   tx_toggles   = tx_toggles   + 1;
always @(posedge clk_rx)   rx_toggles   = rx_toggles   + 1;
always @(posedge clk_baud) baud_toggles = baud_toggles + 1;

task check_gates;
    input exp_tx, exp_rx, exp_baud;
    input [255:0] test_name;
    integer t0_tx, t0_rx, t0_baud;
    begin
        // snapshot toggle counts
        t0_tx   = tx_toggles;
        t0_rx   = rx_toggles;
        t0_baud = baud_toggles;

        // wait 20 clock cycles
        repeat(20) @(posedge clk);

        // check if clocks toggled as expected
        $display("\n--- %s ---", test_name);

        if (exp_tx && (tx_toggles > t0_tx))
            $display("PASS: clk_tx   RUNNING  (toggled %0d times)",
                      tx_toggles - t0_tx);
        else if (!exp_tx && (tx_toggles == t0_tx))
            $display("PASS: clk_tx   GATED    (0 toggles — power saved)");
        else
            $display("FAIL: clk_tx   unexpected behaviour");

        if (exp_rx && (rx_toggles > t0_rx))
            $display("PASS: clk_rx   RUNNING  (toggled %0d times)",
                      rx_toggles - t0_rx);
        else if (!exp_rx && (rx_toggles == t0_rx))
            $display("PASS: clk_rx   GATED    (0 toggles — power saved)");
        else
            $display("FAIL: clk_rx   unexpected behaviour");

        if (exp_baud && (baud_toggles > t0_baud))
            $display("PASS: clk_baud RUNNING  (toggled %0d times)",
                      baud_toggles - t0_baud);
        else if (!exp_baud && (baud_toggles == t0_baud))
            $display("PASS: clk_baud GATED    (0 toggles — power saved)");
        else
            $display("FAIL: clk_baud unexpected behaviour");
    end
endtask

initial begin
    clk       = 0; rst = 1;
    tx_active = 0; rx_active = 0; baud_en = 0;

    repeat(10) @(posedge clk);
    rst = 0;
    repeat(10) @(posedge clk);

    $display("============================================");
    $display("  Clock Gate Testbench");
    $display("  Verifying independent sub-block gating");
    $display("============================================");

    // Test 1: everything off — all clocks gated
    tx_active = 0; rx_active = 0; baud_en = 0;
    check_gates(0, 0, 0, "IDLE: All blocks off");

    // Test 2: TX only active
    tx_active = 1; rx_active = 0; baud_en = 0;
    check_gates(1, 0, 0, "TX ONLY: Only clk_tx running");

    // Test 3: RX only active
    tx_active = 0; rx_active = 1; baud_en = 0;
    check_gates(0, 1, 0, "RX ONLY: Only clk_rx running");

    // Test 4: baud detector only
    tx_active = 0; rx_active = 0; baud_en = 1;
    check_gates(0, 0, 1, "BAUD ONLY: Only clk_baud running");

    // Test 5: full duplex — all on
    tx_active = 1; rx_active = 1; baud_en = 1;
    check_gates(1, 1, 1, "FULL DUPLEX: All clocks running");

    // Test 6: TX+RX, baud off (already locked)
    tx_active = 1; rx_active = 1; baud_en = 0;
    check_gates(1, 1, 0, "TX+RX: baud clock gated (already locked)");

    $display("\n============================================");
    $display("  Clock Gate Tests Complete");
    $display("============================================");
    $finish;
end

initial begin
    $dumpfile("clock_gate.vcd");
    $dumpvars(0, clock_gate_tb);
end

endmodule	