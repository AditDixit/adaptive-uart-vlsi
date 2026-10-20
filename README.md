# Power-Aware Adaptive UART Transceiver
**RTL Design | Functional Verification | Synthesis | Intel MAX 10**

> Designed as part of VLSI coursework at VIT Vellore | ECE 7th Semester

---

## Overview

A UART transceiver in Verilog that combines two hardware ideas aimed at IoT edge devices, where peripheral power matters. The design uses low-power techniques inspired by research on IoT edge applications.

### Innovation 1 - Hardware Automatic Baud Rate Detection
A pure RTL FSM measures the start-bit pulse width against a 50 MHz reference clock and locks onto the baud rate from a **single start bit (~8.7 µs at 115200 bps)**. Supports 9600, 19200, 38400, 57600 and 115200 bps with no software involvement and no manual configuration.

### Innovation 2 - Fine-Grained Independent Clock Gating
The TX block, RX block and baud detector each have their **own latch-based clock gate**, so switching activity is removed only from the blocks that are idle. TX can run while RX is off, and vice versa.

---

## Architecture

```
                      adaptive_uart_top
        +---------------------------------------------------+
        |                                                   |
tx_data |   +---------+                                     |
tx_start+-->| uart_tx |<---- clk_tx ----+                   +--> tx, tx_busy
        |   +---------+                 |                   |
        |                           +---+--------+          |
rx -----+-->+---------+             | clock_gate |          +--> rx_data, rx_valid
        |   | uart_rx |<-- clk_rx --+  (latch    |          |
        |   +---------+             |   ICGs)    |          |
        |                           +---+--------+          |
rx -----+-->+-------------+             |                   +--> baud_locked, baud_div
        |   | baud_detect |<- clk_baud -+                   |
        |   +-------------+                                 |
        |                                                   |
        |  activity logic (tx_start/tx_busy, rx edge +      |
        |  hold timer, ~baud_locked) drives the gate enables|
        +---------------------------------------------------+
```

---

## Module Breakdown

| Module | Description |
|---|---|
| `uart_tx.v` | Parameterised UART transmitter, 8N1, async reset |
| `uart_rx.v` | UART receiver with a 2-flop input synchroniser (no separate glitch filter) |
| `baud_detect.v` | Hardware baud-rate FSM: start-bit measurement and classification |
| `clock_gate.v` | Latch-based clock gates with independent TX / RX / BAUD enables |
| `adaptive_uart_top.v` | Top level: integration and activity-driven clock-enable logic |

---

## Synthesis Results - Intel MAX 10 (10M08DAF484C8G)

Quartus Prime 23.1 Lite:

| Metric | Value |
|---|---|
| Logic Elements | 294 / 8,064 **(4%)** |
| Registers | 162 |
| Total Pins | 47 / 250 (19%) |
| **Fmax** | **169.84 MHz** |
| Operating Frequency | 50 MHz |
| Timing Margin | **3.4x** |
| Total Power | 45.62 mW |
| Core Dynamic Power | 0.00 mW (idle) |
| Core Static Power | 39.76 mW |
| I/O Power | 5.86 mW |

> **Reading the power numbers:** this estimate was taken with an idle design, so the 0.00 mW core dynamic figure only says nothing was switching. It is not a measurement of what clock gating saves, and static power (39.76 mW) cannot be reduced by clock gating. The switching-activity results below are the evidence for the gating benefit.

---

## Verification Results

All testbenches are self-checking. Results below were reproduced with Verilator 5; `adaptive_uart_top_tb` reports a cumulative total, so an early failure cannot be hidden by a later phase.

| Testbench | Test | Result |
|---|---|---|
| `uart_tx_tb` | 9 known bytes, decoded from the tx line | 9/9 PASS |
| `uart_loopback_tb` | 10 known bytes, TX looped to RX at 115200 | 10/10 PASS |
| `baud_detect_tb` | 115200 / 57600 / 38400 / 19200 / 9600 bps | 5/5 LOCKED (div = 434 / 868 / 1302 / 2604 / 5208) |
| `clock_gate_tb` | Idle, TX only, RX only, baud only, full duplex, TX+RX | 18/18 PASS |
| `adaptive_uart_top_tb` | Baud lock (div = 434) | PASS |
| | RX: 10 known bytes + mode check | 13/13 PASS |
| | TX: 5 bytes decoded from the tx line + mode check | 8/8 PASS |
| | Full duplex: simultaneous RX and TX frame + mode check | 5/5 PASS |
| | **Stress test: 500 pseudo-random bytes** | **500/500 PASS** |
| | Sparse traffic: 20 bytes, ~1 ms apart | 20/20 PASS |
| | Idle: all three clocks gated | 3/3 PASS |
| | **Total** | **551 PASS, 0 FAIL** |

---

## Clock Gating Power Modes

Checked by assertion in `adaptive_uart_top_tb` (sampled mid-frame, or after the RX hold timer for idle):

| Operating Mode | TX Clock | RX Clock | Baud Clock |
|---|---|---|---|
| **IDLE** (after lock, hold timer expired) | GATED | GATED | GATED |
| **TX only** | RUNNING | GATED | GATED |
| **RX only** | GATED | RUNNING | GATED |
| **Full duplex** | RUNNING | RUNNING | GATED |
| **Before lock** | GATED | wakes on a start bit | RUNNING |

The baud clock runs from reset until the baud rate is locked, then stays off. The RX clock wakes on a falling edge of `rx` and is held for about 6000 cycles after a start bit and about 2000 cycles after a received byte (about 40 µs at 50 MHz) before gating again.

### Measured clock-enable activity (simulation)

Share of clock cycles in which each gated clock is enabled. A design without clock gating would be 100% for all three.

| Workload | clk_tx | clk_rx | clk_baud |
|---|---|---|---|
| Back-to-back RX traffic (500 bytes, worst case for RX) | 0.00% | 100.00% | 0.00% |
| Sparse RX traffic (20 bytes, ~1 ms apart) | 0.00% | **11.19%** | 0.00% |

These counts come from the clock-enable signals in simulation. They show the reduction in clock activity, not a power figure from Quartus. Gating with fabric logic on an FPGA is not the same as using a dedicated clock-control block, so the technique pays off most in an ASIC flow, where the latch and AND map to a standard-cell clock gate.

---

## Baud Rate Detection - How It Works

```
RX line:  -----+           +------------------
               | START BIT |  DATA BITS ...
               +-----------+
               ^           ^
          falling edge   rising edge
          start counter  stop counter
               |           |
               +--- count -+  = baud period in clock cycles

compare with the known divisors (+/- 3%)
-> lock onto the nearest standard rate
```

Note for testing: a single low pulse is enough to trigger detection, but the running receiver also decodes that pulse as a `0xFF` frame about ten bit-times later. The testbench accounts for this explicitly. In real use, the first frame after reset is consumed by the detection step.

---

## Running the Simulations

```bash
SRC="uart_tx.v uart_rx.v baud_detect.v clock_gate.v adaptive_uart_top.v"

verilator --binary --timing --top-module adaptive_uart_top_tb \
    adaptive_uart_top_tb.v $SRC
./obj_dir/Vadaptive_uart_top_tb
```

The other testbenches are built the same way with their own top module (`uart_tx_tb`, `baud_detect_tb`, `clock_gate_tb`, `uart_loopback_tb`). If the C++ build fails with coroutine errors, add `-CFLAGS "-std=c++20 -fcoroutines"`. The testbenches also run in ModelSim-Intel.

---

## Tools Used

- **Verilog HDL** - RTL design
- **ModelSim-Intel** - functional simulation during development
- **Verilator 5** - reproduction of the results in this README
- **Quartus Prime 23.1 Lite** - synthesis, STA, power analysis
- **Target device** - Intel MAX 10 (10M08DAF484C8G)

---

## Author

Aditya Dixit
B.Tech ECE | VIT Vellore | Target: VLSI Physical Design / Verification Engineer
