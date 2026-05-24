// ============================================================
// Testbench : uart_tx_tb
// Tests     : Single byte, multiple bytes, busy signal
// ============================================================

`timescale 1ns/1ps

module uart_tx_tb;

// ── parameters ────────────────────────────────────────────────
localparam CLK_FREQ  = 50_000_000;
localparam BAUD_RATE = 115200;
localparam BAUD_PERIOD_NS = 1_000_000_000 / BAUD_RATE; // ~8680 ns
localparam CLK_PERIOD     = 20; // 50 MHz = 20 ns period

// ── DUT signals ───────────────────────────────────────────────
reg        clk;
reg        rst;
reg  [7:0] tx_data;
reg        tx_start;
wire       tx;
wire       tx_busy;

// ── instantiate DUT ───────────────────────────────────────────
uart_tx #(
    .CLK_FREQ  (CLK_FREQ),
    .BAUD_RATE (BAUD_RATE)
) DUT (
    .clk      (clk),
    .rst      (rst),
    .tx_data  (tx_data),
    .tx_start (tx_start),
    .tx       (tx),
    .tx_busy  (tx_busy)
);

// ── clock generation ──────────────────────────────────────────
always #(CLK_PERIOD/2) clk = ~clk;

// ── task: send one byte and verify on TX line ─────────────────
task send_byte;
    input [7:0] data;
    integer i;
    reg [7:0] received;
    begin
        // apply data and pulse tx_start
        @(negedge clk);
        tx_data  = data;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;

        // wait for start bit
        @(negedge tx);
        #(BAUD_PERIOD_NS / 2); // sample mid-bit

        // check start bit is 0
        if (tx !== 1'b0)
            $display("ERROR: Start bit not 0 for data %h", data);

        // sample each data bit at mid-bit point
        for (i = 0; i < 8; i = i + 1) begin
            #(BAUD_PERIOD_NS);
            received[i] = tx;
        end

        // check stop bit
        #(BAUD_PERIOD_NS);
        if (tx !== 1'b1)
            $display("ERROR: Stop bit not 1 for data %h", data);

        // verify received matches sent
        if (received === data)
            $display("PASS: Sent 0x%h | Received 0x%h", data, received);
        else
            $display("FAIL: Sent 0x%h | Received 0x%h", data, received);

        // wait for busy to deassert
        @(negedge tx_busy);
    end
endtask

// ── test stimulus ─────────────────────────────────────────────
initial begin
    // initialise
    clk      = 0;
    rst      = 1;
    tx_data  = 8'd0;
    tx_start = 0;

    // release reset
    repeat(5) @(posedge clk);
    rst = 0;
    repeat(5) @(posedge clk);

    $display("============================================");
    $display("  UART TX Testbench — Starting Tests");
    $display("============================================");

    // Test 1: single known byte
    $display("\nTest 1: Single byte 0x55 (alternating bits)");
    send_byte(8'h55);

    // Test 2: all zeros
    $display("\nTest 2: 0x00 (all zeros)");
    send_byte(8'h00);

    // Test 3: all ones
    $display("\nTest 3: 0xFF (all ones)");
    send_byte(8'hFF);

    // Test 4: consecutive bytes
    $display("\nTest 4: Consecutive bytes A, B, C");
    send_byte(8'h41); // 'A'
    send_byte(8'h42); // 'B'
    send_byte(8'h43); // 'C'

    // Test 5: random bytes
    $display("\nTest 5: Random bytes");
    send_byte(8'hA3);
    send_byte(8'h7F);
    send_byte(8'h2D);

    $display("\n============================================");
    $display("  All Tests Complete");
    $display("============================================");

    #(BAUD_PERIOD_NS * 5);
    $finish;
end

// ── waveform dump ─────────────────────────────────────────────
initial begin
    $dumpfile("uart_tx.vcd");
    $dumpvars(0, uart_tx_tb);
end

endmodule