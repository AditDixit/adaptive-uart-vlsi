// ============================================================
// Project  : Power-Aware Adaptive UART Transceiver
// Module   : clock_gate
// Author   : [Your Name] | VIT Vellore | ECE 7th Sem
// Date     : May 2026
// ============================================================

module clock_gate (
    input  wire clk,
    input  wire rst,
    input  wire tx_active,
    input  wire rx_active,
    input  wire baud_en,
    output wire clk_tx,
    output wire clk_rx,
    output wire clk_baud
);

reg latch_tx, latch_rx, latch_baud;

always @(*) begin
    if (!clk) latch_tx   = tx_active | rst;
end
always @(*) begin
    if (!clk) latch_rx   = rx_active | rst;
end
always @(*) begin
    if (!clk) latch_baud = baud_en   | rst;
end

assign clk_tx   = clk & latch_tx;
assign clk_rx   = clk & latch_rx;
assign clk_baud = clk & latch_baud;

endmodule