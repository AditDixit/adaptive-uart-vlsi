`timescale 1ns/1ps

module uart_loopback_tb;

localparam CLK_FREQ       = 50_000_000;
localparam BAUD_RATE      = 115200;
localparam CLK_PERIOD     = 20;
localparam BAUD_PERIOD_NS = 1_000_000_000 / BAUD_RATE; // ~8680ns
localparam TIMEOUT_CLKS   = CLK_FREQ / BAUD_RATE * 15; // 15 baud periods

// ?? signals ???????????????????????????????????????????????????
reg        clk, rst;
reg  [7:0] tx_data;
reg        tx_start;
wire       tx, tx_busy;
wire [7:0] rx_data;
wire       rx_valid;
wire       rx_error;

// ?? loopback connection ???????????????????????????????????????
uart_tx #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE)) TX (
    .clk(clk),.rst(rst),
    .tx_data(tx_data),.tx_start(tx_start),
    .tx(tx),.tx_busy(tx_busy)
);

uart_rx #(.CLK_FREQ(CLK_FREQ),.BAUD_RATE(BAUD_RATE)) RX (
    .clk(clk),.rst(rst),
    .rx(tx),              // TX wired directly to RX
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .rx_error(rx_error)
);

// ?? clock ?????????????????????????????????????????????????????
always #(CLK_PERIOD/2) clk = ~clk;

// ?? counters ??????????????????????????????????????????????????
integer pass_count;
integer fail_count;

// ?? send byte task ????????????????????????????????????????????
// sends a byte, then polls for rx_valid with timeout
task send_and_check;
    input [7:0] data;
    integer timeout;
    reg     got_valid;
    begin
        // wait until not busy
        timeout = 0;
        while (tx_busy && timeout < TIMEOUT_CLKS) begin
            @(posedge clk); timeout = timeout + 1;
        end

        // send the byte
        @(negedge clk);
        tx_data  = data;
        tx_start = 1'b1;
        @(negedge clk);
        tx_start = 1'b0;

        // poll for rx_valid ? no blocking wait
        got_valid = 0;
        timeout   = 0;
        while (!got_valid && timeout < TIMEOUT_CLKS) begin
            @(posedge clk);
            timeout = timeout + 1;
            if (rx_valid) begin
                got_valid = 1;
                if (rx_data === data) begin
                    $display("PASS: Sent 0x%h | Received 0x%h",
                              data, rx_data);
                    pass_count = pass_count + 1;
                end else begin
                    $display("FAIL: Sent 0x%h | Got 0x%h",
                              data, rx_data);
                    fail_count = fail_count + 1;
                end
            end
        end

        if (!got_valid) begin
            $display("TIMEOUT: No response for byte 0x%h", data);
            fail_count = fail_count + 1;
        end

        // gap between bytes ? 2 full baud periods
        repeat(BAUD_PERIOD_NS / CLK_PERIOD * 2) @(posedge clk);
    end
endtask

// ?? main test ?????????????????????????????????????????????????
initial begin
    clk        = 0;
    rst        = 1;
    tx_data    = 0;
    tx_start   = 0;
    pass_count = 0;
    fail_count = 0;

    repeat(20) @(posedge clk);
    rst = 0;
    repeat(20) @(posedge clk);

    $display("============================================");
    $display("  UART Loopback Testbench");
    $display("  Baud: %0d | Clk: %0d Hz", BAUD_RATE, CLK_FREQ);
    $display("============================================");

    send_and_check(8'h55);   // 01010101 alternating
    send_and_check(8'hAA);   // 10101010 alternating
    send_and_check(8'h00);   // all zeros
    send_and_check(8'hFF);   // all ones
    send_and_check(8'h41);   // 'A'
    send_and_check(8'h42);   // 'B'
    send_and_check(8'h43);   // 'C'
    send_and_check(8'hA3);
    send_and_check(8'h7F);
    send_and_check(8'h2D);

    $display("============================================");
    $display("  PASS: %0d | FAIL: %0d", pass_count, fail_count);
    if (fail_count == 0)
        $display("  ALL TESTS PASSED");
    else
        $display("  FAILURES DETECTED");
    $display("============================================");

    $finish;
end

initial begin
    $dumpfile("uart_loopback.vcd");
    $dumpvars(0, uart_loopback_tb);
end

endmodule