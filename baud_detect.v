// ============================================================
// Project  : Power-Aware Adaptive UART Transceiver
// Module   : baud_detect
// Author   : [Your Name] | VIT Vellore | ECE 7th Sem
// Date     : May 2026
// ============================================================

module baud_detect #(
    parameter CLK_FREQ = 50_000_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        rx,
    output reg  [15:0] baud_div,
    output reg         baud_locked,
    output reg  [2:0]  baud_index
);

localparam DIV_9600   = CLK_FREQ / 9600;
localparam DIV_19200  = CLK_FREQ / 19200;
localparam DIV_38400  = CLK_FREQ / 38400;
localparam DIV_57600  = CLK_FREQ / 57600;
localparam DIV_115200 = CLK_FREQ / 115200;

localparam TOL_9600_HI   = DIV_9600   + (DIV_9600   / 33);
localparam TOL_9600_LO   = DIV_9600   - (DIV_9600   / 33);
localparam TOL_19200_HI  = DIV_19200  + (DIV_19200  / 33);
localparam TOL_19200_LO  = DIV_19200  - (DIV_19200  / 33);
localparam TOL_38400_HI  = DIV_38400  + (DIV_38400  / 33);
localparam TOL_38400_LO  = DIV_38400  - (DIV_38400  / 33);
localparam TOL_57600_HI  = DIV_57600  + (DIV_57600  / 33);
localparam TOL_57600_LO  = DIV_57600  - (DIV_57600  / 33);
localparam TOL_115200_HI = DIV_115200 + (DIV_115200 / 33);
localparam TOL_115200_LO = DIV_115200 - (DIV_115200 / 33);

reg rx_s1, rx_s2, rx_s3;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_s1 <= 1'b1;
        rx_s2 <= 1'b1;
        rx_s3 <= 1'b1;
    end else begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
        rx_s3 <= rx_s2;
    end
end

wire rx_clean    = rx_s2;
wire falling_edge = (rx_s3 == 1'b1) && (rx_s2 == 1'b0);

localparam WAIT_FALL   = 2'd0;
localparam MEASURING   = 2'd1;
localparam CLASSIFYING = 2'd2;
localparam LOCKED      = 2'd3;

reg [1:0]  state;
reg [15:0] pulse_cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state       <= WAIT_FALL;
        pulse_cnt   <= 16'd0;
        baud_div    <= 16'd0;
        baud_locked <= 1'b0;
        baud_index  <= 3'd0;
    end
    else begin
        case (state)
            WAIT_FALL: begin
                baud_locked <= 1'b0;
                pulse_cnt   <= 16'd0;
                if (falling_edge)
                    state <= MEASURING;
            end
            MEASURING: begin
                if (rx_clean == 1'b0)
                    pulse_cnt <= pulse_cnt + 1;
                else
                    state <= CLASSIFYING;
            end
            CLASSIFYING: begin
                if (pulse_cnt >= TOL_9600_LO &&
                    pulse_cnt <= TOL_9600_HI) begin
                    baud_div    <= DIV_9600;
                    baud_index  <= 3'd0;
                    baud_locked <= 1'b1;
                    state       <= LOCKED;
                end
                else if (pulse_cnt >= TOL_19200_LO &&
                         pulse_cnt <= TOL_19200_HI) begin
                    baud_div    <= DIV_19200;
                    baud_index  <= 3'd1;
                    baud_locked <= 1'b1;
                    state       <= LOCKED;
                end
                else if (pulse_cnt >= TOL_38400_LO &&
                         pulse_cnt <= TOL_38400_HI) begin
                    baud_div    <= DIV_38400;
                    baud_index  <= 3'd2;
                    baud_locked <= 1'b1;
                    state       <= LOCKED;
                end
                else if (pulse_cnt >= TOL_57600_LO &&
                         pulse_cnt <= TOL_57600_HI) begin
                    baud_div    <= DIV_57600;
                    baud_index  <= 3'd3;
                    baud_locked <= 1'b1;
                    state       <= LOCKED;
                end
                else if (pulse_cnt >= TOL_115200_LO &&
                         pulse_cnt <= TOL_115200_HI) begin
                    baud_div    <= DIV_115200;
                    baud_index  <= 3'd4;
                    baud_locked <= 1'b1;
                    state       <= LOCKED;
                end
                else begin
                    baud_locked <= 1'b0;
                    state       <= WAIT_FALL;
                end
            end
            LOCKED: begin
                baud_locked <= 1'b1;
            end
            default: state <= WAIT_FALL;
        endcase
    end
end

endmodule