`timescale 1ns/1ps

module baud_detect_tb;

localparam CLK_FREQ   = 50_000_000;
localparam CLK_PERIOD = 20; // 50 MHz

reg        clk, rst;
reg        rx_drive;
wire[15:0] baud_div;
wire       baud_locked;
wire[2:0]  baud_index;

baud_detect #(.CLK_FREQ(CLK_FREQ)) DUT (
    .clk        (clk),
    .rst        (rst),
    .rx         (rx_drive),
    .baud_div   (baud_div),
    .baud_locked(baud_locked),
    .baud_index (baud_index)
);

always #(CLK_PERIOD/2) clk = ~clk;

// ── task: simulate one start bit at given baud rate ───────────
task simulate_start_bit;
    input integer baud_rate;
    input [63:0]  baud_name; // just for display
    integer baud_period_ns;
    begin
        baud_period_ns = 1_000_000_000 / baud_rate;
        $display("\nTesting baud rate: %0d bps", baud_rate);

        // idle — line HIGH
        rx_drive = 1'b1;
        #(baud_period_ns * 3);

        // start bit — pull LOW for exactly one baud period
        rx_drive = 1'b0;
        #(baud_period_ns);

        // release HIGH (simulate first data bit = 1)
        rx_drive = 1'b1;

        // wait for lock
        #(CLK_PERIOD * 20);

        // report result
        if (baud_locked) begin
            $display("PASS: Detected baud_div=%0d | index=%0d",
                      baud_div, baud_index);
        end else begin
            $display("FAIL: baud_locked not asserted");
        end

        // reset for next test
        rst = 1;
        #(CLK_PERIOD * 10);
        rst = 0;
        #(CLK_PERIOD * 10);
    end
endtask

initial begin
    clk      = 0;
    rst      = 1;
    rx_drive = 1'b1;

    repeat(20) @(posedge clk);
    rst = 0;
    repeat(20) @(posedge clk);

    $display("============================================");
    $display("  Baud Rate Auto-Detection Testbench");
    $display("============================================");

    simulate_start_bit(115200, "115200");
    simulate_start_bit(57600,  "57600 ");
    simulate_start_bit(38400,  "38400 ");
    simulate_start_bit(19200,  "19200 ");
    simulate_start_bit(9600,   "9600  ");

    $display("\n============================================");
    $display("  All baud rates tested");
    $display("============================================");
    $finish;
end

initial begin
    $dumpfile("baud_detect.vcd");
    $dumpvars(0, baud_detect_tb);
end

endmodule