`timescale 1ns/1ps

// ============================================================
// Testbench : clock-enable activity versus traffic rate
//
// Locks the baud rate, then sends NBYTES bytes in one direction with
// GAP_NS of idle line/time between bytes, and reports the share of
// cycles each gated clock is enabled. One machine-readable line is
// printed at the end:
//
//   SWEEP dir=<RX|TX> gap_us=<n> cycles=<n> tx=<pct> rx=<pct> baud=<pct>
//
// Parameters (override with the simulator's -G option):
//   GAP_NS  idle time after each byte (default 1 ms)
//   DIR     0 = receive traffic, 1 = transmit traffic
//   NBYTES  bytes per run
//
// Example build command (Verilator 5):
//   $ verilator --binary --timing --top-module uart_activity_sweep_tb \
//       -GGAP_NS=1000000 -GDIR=0 uart_activity_sweep_tb.v \
//       uart_tx.v uart_rx.v baud_detect.v clock_gate.v adaptive_uart_top.v
// ============================================================
module uart_activity_sweep_tb #(
    parameter integer GAP_NS = 1_000_000,
    parameter integer DIR    = 0,
    parameter integer NBYTES = 10
);

localparam CLK_FREQ   = 50_000_000;
localparam CLK_PERIOD = 20;
localparam BAUD       = 115200;
localparam BIT_NS     = 1_000_000_000 / BAUD;

reg         clk = 0, rst = 1;
reg  [7:0]  tx_data = 0;
reg         tx_start = 0;
wire        tx, tx_busy;
reg         rx_drive = 1;
wire [7:0]  rx_data;
wire        rx_valid, rx_error, baud_locked;
wire [2:0]  baud_index;
wire [15:0] baud_div;
wire        clk_tx_active, clk_rx_active, clk_baud_active;

adaptive_uart_top #(.CLK_FREQ(CLK_FREQ)) DUT (
    .clk(clk), .rst(rst),
    .tx_data(tx_data), .tx_start(tx_start), .tx(tx), .tx_busy(tx_busy),
    .rx(rx_drive), .rx_data(rx_data), .rx_valid(rx_valid), .rx_error(rx_error),
    .baud_locked(baud_locked), .baud_index(baud_index), .baud_div(baud_div),
    .clk_tx_active(clk_tx_active), .clk_rx_active(clk_rx_active),
    .clk_baud_active(clk_baud_active)
);

always #(CLK_PERIOD/2) clk = ~clk;

// Clock-enable activity counters
integer act_total = 0, act_tx = 0, act_rx = 0, act_baud = 0;
reg     act_en = 0;
always @(posedge clk) if (act_en) begin
    act_total = act_total + 1;
    if (clk_tx_active)   act_tx   = act_tx   + 1;
    if (clk_rx_active)   act_rx   = act_rx   + 1;
    if (clk_baud_active) act_baud = act_baud + 1;
end

integer rx_got = 0;
always @(posedge clk) if (rx_valid && act_en) rx_got = rx_got + 1;

task rx_send_byte;
    input [7:0] data;
    integer i;
    begin
        rx_drive = 1'b0;  #(BIT_NS);
        for (i = 0; i < 8; i = i + 1) begin rx_drive = data[i]; #(BIT_NS); end
        rx_drive = 1'b1;  #(BIT_NS * 2);
    end
endtask

task tx_send_byte;
    input [7:0] data;
    begin
        @(negedge clk); tx_data = data; tx_start = 1'b1;
        @(negedge clk); tx_start = 1'b0;
        #(BIT_NS * 11);                       // frame is 10 bit-times
    end
endtask

integer n;
real pct_tx, pct_rx, pct_baud;

initial begin
    repeat(20) @(posedge clk);
    rst = 0;
    repeat(20) @(posedge clk);

    // Baud lock with a lone start-bit pulse (see adaptive_uart_top_tb)
    rx_drive = 1'b1; #(BIT_NS * 2);
    rx_drive = 1'b0; #(BIT_NS);
    rx_drive = 1'b1; #(BIT_NS * 14);
    // let the RX hold timer expire so the window starts from a gated state
    repeat(8000) @(posedge clk);

    if (!baud_locked) begin
        $display("ERROR: baud not locked");
        $finish;
    end

    act_total = 0; act_tx = 0; act_rx = 0; act_baud = 0;
    act_en = 1;

    for (n = 0; n < NBYTES; n = n + 1) begin
        if (DIR == 0) rx_send_byte(8'hA5 ^ n[7:0]);
        else          tx_send_byte(8'hA5 ^ n[7:0]);
        #(GAP_NS);
    end

    act_en = 0;
    pct_tx   = (100.0 * act_tx)   / act_total;
    pct_rx   = (100.0 * act_rx)   / act_total;
    pct_baud = (100.0 * act_baud) / act_total;
    $display("SWEEP dir=%0s gap_us=%0d cycles=%0d tx=%0.2f rx=%0.2f baud=%0.2f",
             (DIR == 0) ? "RX" : "TX", GAP_NS / 1000, act_total,
             pct_tx, pct_rx, pct_baud);
    if (DIR == 0 && rx_got != NBYTES)
        $display("WARNING: received %0d of %0d bytes", rx_got, NBYTES);
    $finish;
end

endmodule
