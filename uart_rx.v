// ============================================================
// Project  : Power-Aware Adaptive UART Transceiver
// Module   : uart_rx
// Author   : [Your Name] | VIT Vellore | ECE 7th Sem
// Date     : May 2026
// ============================================================

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_error
);

localparam BAUD_DIV  = CLK_FREQ / BAUD_RATE;
localparam HALF_BAUD = BAUD_DIV / 2;

localparam IDLE  = 2'd0;
localparam START = 2'd1;
localparam DATA  = 2'd2;
localparam STOP  = 2'd3;

reg [1:0] state;
reg [2:0] bit_idx;
reg [7:0] rx_shift;
integer   baud_cnt;

// 2-flop synchroniser
reg rx_sync1, rx_sync2;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_sync1 <= 1'b1;
        rx_sync2 <= 1'b1;
    end else begin
        rx_sync1 <= rx;
        rx_sync2 <= rx_sync1;
    end
end

wire rx_clean = rx_sync2;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state    <= IDLE;
        rx_data  <= 8'd0;
        rx_valid <= 1'b0;
        rx_error <= 1'b0;
        baud_cnt <= 0;
        bit_idx  <= 0;
        rx_shift <= 8'd0;
    end
    else begin
        rx_valid <= 1'b0;
        rx_error <= 1'b0;

        case (state)
            IDLE: begin
                baud_cnt <= 0;
                bit_idx  <= 0;
                if (rx_clean == 1'b0)
                    state <= START;
            end
            START: begin
                if (baud_cnt < HALF_BAUD - 1)
                    baud_cnt <= baud_cnt + 1;
                else begin
                    baud_cnt <= 0;
                    if (rx_clean == 1'b0)
                        state <= DATA;
                    else
                        state <= IDLE;
                end
            end
            DATA: begin
                if (baud_cnt < BAUD_DIV - 1)
                    baud_cnt <= baud_cnt + 1;
                else begin
                    baud_cnt <= 0;
                    rx_shift <= {rx_clean, rx_shift[7:1]};
                    if (bit_idx < 7)
                        bit_idx <= bit_idx + 1;
                    else begin
                        bit_idx <= 0;
                        state   <= STOP;
                    end
                end
            end
            STOP: begin
                if (baud_cnt < BAUD_DIV - 1)
                    baud_cnt <= baud_cnt + 1;
                else begin
                    baud_cnt <= 0;
                    if (rx_clean == 1'b1) begin
                        rx_data  <= rx_shift;
                        rx_valid <= 1'b1;
                    end else
                        rx_error <= 1'b1;
                    state <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

endmodule