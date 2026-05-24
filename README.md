# Power-Aware Adaptive UART Transceiver
**RTL Design | Functional Verification | Synthesis | Intel MAX 10**

> Designed as part of VLSI coursework at VIT Vellore | ECE 7th Semester

---

## Overview

A novel UART transceiver architecture in Verilog combining two hardware
innovations targeting IoT edge devices where peripheral power dominates
system energy budget.

### Innovation 1 — Hardware Automatic Baud Rate Detection
Pure RTL FSM measures start-bit pulse width using a 50 MHz reference
clock to auto-detect baud rate in exactly **one start bit (~8.7μs at
115200 bps)**. Supports 9600, 19200, 38400, 57600, and 115200 bps.
Zero software overhead. Zero manual configuration.

### Innovation 2 — Fine-Grained Independent Clock Gating
TX block, RX block, and baud generator each have **independent
latch-based clock gate cells** — eliminating switching activity in
inactive paths only. TX clock runs while RX clock is fully off and
vice versa.

---

## Architecture
    ┌─────────────────────────────────┐
                │      adaptive_uart_top           │
                │                                  │
tx_data ─────────►  ┌──────────┐   clk_tx           │
tx_start ────────►  │ uart_tx  │◄──────────┐        │──► tx
│  └──────────┘           │        │
│                         │        │
rx ──────────────►  ┌──────────┐   clk_rx  │        │
│  │ uart_rx  │◄────────┐ │        │──► rx_data
│  └──────────┘         │ │        │──► rx_valid
│                       │ │        │
rx ──────────────►  ┌─────────────┐       │ │        │
│  │ baud_detect │       │ │        │──► baud_locked
│  └─────────────┘       │ │        │──► baud_div
│        │clk_baud       │ │        │
│        ▼               │ │        │
│  ┌────────────┐        │ │        │
│  │ clock_gate │────────┘─┘        │
│  └────────────┘                   │
└─────────────────────────────────┘


---

## Module Breakdown

| Module | Description |
|---|---|
| `uart_tx.v` | Parameterised UART transmitter — 8N1, async reset |
| `uart_rx.v` | UART receiver with 2-flop synchroniser, glitch filtering |
| `baud_detect.v` | Hardware baud rate FSM — start-bit measurement + classification |
| `clock_gate.v` | Latch-based ICG cells — independent TX/RX/BAUD gating |
| `adaptive_uart_top.v` | Top-level integration with activity-driven clock control |

---

## Synthesis Results — Intel MAX 10 (10M08DAF484C8G)

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
| Tool | Quartus Prime 23.1 Lite |

---

## Verification Results

| Test | Result |
|---|---|
| UART TX — 9 known bytes | ✅ 9/9 PASS |
| UART RX — 10 known bytes | ✅ 10/10 PASS |
| Baud Detection — 115200 bps | ✅ LOCKED (div=434) |
| Baud Detection — 57600 bps | ✅ LOCKED (div=868) |
| Baud Detection — 38400 bps | ✅ LOCKED (div=1302) |
| Baud Detection — 19200 bps | ✅ LOCKED (div=2604) |
| Baud Detection — 9600 bps | ✅ LOCKED (div=5208) |
| Clock Gate — IDLE | ✅ All 3 clocks gated |
| Clock Gate — TX only | ✅ Only clk_tx running |
| Clock Gate — RX only | ✅ Only clk_rx running |
| **Stress Test — 500 random bytes** | ✅ **500/500 PASS** |

---

## Clock Gating Power Modes

| Operating Mode | TX Clock | RX Clock | Baud Clock |
|---|---|---|---|
| **IDLE** | GATED | GATED | GATED |
| **TX Only** | RUNNING | GATED | GATED |
| **RX Only** | GATED | RUNNING | GATED |
| **Full Duplex** | RUNNING | RUNNING | GATED* |
| **Detecting** | GATED | RUNNING | RUNNING |

*Baud clock gates automatically after lock — stays off for rest of operation

---

## Baud Rate Detection — How It Works
RX line:  ─────┐           ┌──────────────────
│ START BIT │  DATA BITS...
└───────────┘
↑           ↑
falling edge   rising edge
start counter  stop counter
│           │
└─── count ─┘ = baud_period in clock cycles
compare to known divisors ±3%
→ lock onto nearest standard rate


---

## Tools Used

- **Verilog HDL** — RTL design
- **ModelSim-Intel** — Functional simulation
- **Quartus Prime 23.1 Lite** — Synthesis, STA, Power Analysis
- **Target Device** — Intel MAX 10 (10M08DAF484C8G)

---

## Publication

Work being prepared for submission to **IEEE NEWCAS 2027**
(New Circuits and Systems Conference)

---

## Author

Aditya Dixit
B.Tech ECE | VIT Vellore | Target: VLSI Physical Design / Verification Engineer

