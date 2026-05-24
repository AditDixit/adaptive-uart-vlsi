// ============================================================
// Project  : Power-Aware Adaptive UART Transceiver
// Module   : uart_tx
// Author   : [Your Name] | VIT Vellore | ECE 7th Sem
// Date     : May 2026
// ============================================================

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] tx_data,
    input  wire       tx_start,
    output reg        tx,
    output reg        tx_busy
);

localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

localparam IDLE  = 2'd0;
localparam START = 2'd1;
localparam DATA  = 2'd2;
localparam STOP  = 2'd3;

reg [1:0] state;
reg [2:0] bit_idx;
reg [7:0] tx_shift;
integer   baud_cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state    <= IDLE;
        tx       <= 1'b1;
        tx_busy  <= 1'b0;
        baud_cnt <= 0;
        bit_idx  <= 0;
        tx_shift <= 8'd0;
    end
    else begin
        case (state)
            IDLE: begin
                tx       <= 1'b1;
                tx_busy  <= 1'b0;
                baud_cnt <= 0;
                bit_idx  <= 0;
                if (tx_start) begin
                    tx_shift <= tx_data;
                    tx_busy  <= 1'b1;
                    state    <= START;
                end
            end
            START: begin
                tx <= 1'b0;
                if (baud_cnt < BAUD_DIV - 1)
                    baud_cnt <= baud_cnt + 1;
                else begin
                    baud_cnt <= 0;
                    state    <= DATA;
                end
            end
            DATA: begin
                tx <= tx_shift[0];
                if (baud_cnt < BAUD_DIV - 1)
                    baud_cnt <= baud_cnt + 1;
                else begin
                    baud_cnt <= 0;
                    tx_shift <= tx_shift >> 1;
                    if (bit_idx < 7)
                        bit_idx <= bit_idx + 1;
                    else begin
                        bit_idx <= 0;
                        state   <= STOP;
                    end
                end
            end
            STOP: begin
                tx <= 1'b1;
                if (baud_cnt < BAUD_DIV - 1)
                    baud_cnt <= baud_cnt + 1;
                else begin
                    baud_cnt <= 0;
                    tx_busy  <= 1'b0;
                    state    <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule