# 🚀 Memory-Efficient INT8 Neural Processing Unit (NPU) for RISC-V Edge AI

<div align="center">

[![RISC-V](https://img.shields.io/badge/Architecture-RISC--V%20RV32I-orange.svg?style=for-the-badge&logo=riscv&logoColor=white)](https://riscv.org/)
[![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Spartan--7%20XC7S50-red.svg?style=for-the-badge&logo=amd&logoColor=white)](https://www.realdigital.org/hardware/boolean)
[![Speedup](https://img.shields.io/badge/Acceleration-497.6x%20Faster-brightgreen.svg?style=for-the-badge&logo=fastapi&logoColor=white)](#-performance--benchmark-results)
[![Accuracy](https://img.shields.io/badge/Accuracy-95.00%25%20INT8-blue.svg?style=for-the-badge&logo=pytorch&logoColor=white)](#-neural-network-training--quantization)
[![Vivado](https://img.shields.io/badge/EDA-Vivado%202025.2-purple.svg?style=for-the-badge&logo=xilinx&logoColor=white)](https://www.xilinx.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)

**An ultra-compact, memory-efficient Hardware INT8 Neural Processing Unit (NPU) peripheral integrated with the PicoRV32 RISC-V processor on the Real Digital Spartan-7 Boolean FPGA Board.**

*Accelerates MNIST handwritten digit recognition in **12,784 clock cycles (128 µs)** with live interactive touch drawing and real-time physical 7-segment display output.*

[Architecture](#-system-architecture) • [Benchmarks](#-performance--benchmark-results) • [Hardware Pinout](#-hardware-pinout-boolean-board) • [Repository Structure](#-repository-structure) • [Quick Start](#-quick-start-guide)

</div>

---

## 🌟 Key Highlights & Novelty

- ⚡ **497.6&times; Hardware Acceleration:** Reduces neural network inference from **6,362,190 clock cycles** (pure CPU software) down to **12,784 clock cycles** on dedicated FPGA MAC hardware.
- 🎯 **Zero Accuracy Loss Quantization:** Symmetric INT8 quantization achieves **95.00% accuracy** on MNIST test set (+0.04% vs 94.96% FP32 reference).
- 💾 **Memory Footprint < 25 KB:** Fits strictly within resource-constrained edge budgets using synchronous Block RAM (`(* ram_style = "block" *)`), consuming **< 20% of chip BRAM**.
- 🛠️ **Pure Logic Arithmetic (0 DSPs):** High-speed INT8 MAC unit is mapped purely into LUT logic, saving 100% of FPGA DSP slices for other system tasks.
- 🖐️ **Live Touch Drawing to Physical Display:** Interactive desktop touch canvas captures handwritten digits, preprocesses them via Center-of-Mass alignment, and displays the recognized digit live on the Spartan-7 board's **onboard 7-segment display** (`d - X`).

---

## 📐 System Architecture

```
                             HOST COMPUTER
                                   │
               ┌───────────────────┴───────────────────┐
               │    Python Machine Learning & Bridge    │
               │  • PyTorch INT8 Quantization Engine   │
               │  • Live Touch Canvas (28x28 Center)   │
               └───────────────────┬───────────────────┘
                                   │ USB-UART (115,200 Baud)
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                 REAL DIGITAL SPARTAN-7 BOOLEAN BOARD (XC7S50)               │
│                                                                             │
│  ┌──────────────────────┐                     ┌──────────────────────────┐  │
│  │   Boot ROM (32 KB)   │                     │  Application RAM (8 KB)  │  │
│  │   (firmware.hex)     │                     │  (Stack, .data, .bss)    │  │
│  └──────────┬───────────┘                     └─────────────┬────────────┘  │
│             │                                               │               │
│             ▼                                               ▼               │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                     PicoRV32 RISC-V CPU Core (RV32I)                  │  │
│  └──────────────────────────────────┬────────────────────────────────────┘  │
│                                     │ Native 32-bit Memory-Mapped Bus       │
│             ┌───────────────────────┼────────────────────────┐              │
│             │                       │                        │              │
│             ▼                       ▼                        ▼              │
│  ┌────────────────────┐   ┌───────────────────┐   ┌──────────────────────┐  │
│  │  UART Transceiver  │   │  Input Image BRAM │   │   Custom INT8 NPU    │  │
│  │  (115.2k Baud)     │   │  (1024 Bytes DP)  │   │   Peripheral Core    │  │
│  └────────────────────┘   └─────────┬─────────┘   └──────────┬───────────┘  │
│                                     │ Port B Read            │              │
│                                     └────────────┬───────────┘              │
│                                                  ▼                          │
│                                       ┌──────────────────────┐              │
│                                       │ Pipelined MAC Unit   │              │
│                                       │ • Signed INT8 x INT8 │              │
│                                       │ • 32-bit Accumulator │              │
│                                       │ • ReLU + Shift (10)  │              │
│                                       │ • Parallel Argmax    │              │
│                                       └──────────┬───────────┘              │
│                                                  │                          │
│                                                  ▼ Winning Digit (0-9)      │
│                                       ┌──────────────────────┐              │
│                                       │ 7-Segment Controller │              │
│                                       │ (1.5 kHz Multiplex)  │              │
│                                       └──────────┬───────────┘              │
└──────────────────────────────────────────────────┼──────────────────────────┘
                                                   │
                                                   ▼
                                     ┌──────────────────────────┐
                                     │ Onboard 7-Segment LED    │
                                     │ Active-Low Common-Anode  │
                                     │ Output: [ d ] [ - ] [ 7] │
                                     └──────────────────────────┘
```

---

## 📊 Performance & Benchmark Results

Measured directly on hardware running on the **Spartan-7 Boolean Board @ 100 MHz**:

| Metric | PicoRV32 Soft CPU Baseline | Custom INT8 NPU Accelerator | Improvement |
| :--- | :---: | :---: | :---: |
| **Execution Latency** | **6,362,190 clock cycles** | **12,784 clock cycles** | **497.6&times; Faster** |
| **Inference Time** | 63.62 milliseconds | **0.128 milliseconds (128 µs)** | **Real-Time Edge AI** |
| **Throughput** | ~15.7 inferences / sec | **~7,820 inferences / sec** | **500x Throughput** |
| **Model Classification** | MNIST ($784 \to 16 \to 10$) | MNIST ($784 \to 16 \to 10$) | Exact Match |
| **Test Accuracy** | 94.96% (FP32 PyTorch) | **95.00% (INT8 Quantized)** | **+0.04% Gain** |
| **BRAM Utilization** | 10 Blocks (ROM + RAM) | 4 Blocks (Total SoC) | **< 20% of chip BRAM** |
| **DSP Utilization** | 0 DSP slices | **0 DSP slices** | **100% DSPs Free** |
| **Timing Slack (WNS)** | N/A | **+0.919 ns @ 100 MHz** | **Zero Violations** |

---

## 🗂️ Repository Structure

The codebase is organized into **three distinct, cleanly separated directories**:

```
.
├── verilog/                   # Hardware Description (RTL), Constraints & Simulation
│   ├── rtl/                   # Synthesizable Verilog modules
│   │   ├── picorv32_npu_top.v # SoC Top interconnecting CPU, NPU, memory & peripherals
│   │   ├── picorv32.v         # PicoRV32 RISC-V RV32I Processor core
│   │   ├── npu_controller.v   # NPU FSM, address generator, ReLU & Argmax engine
│   │   ├── npu_mac.v          # Signed INT8 MAC unit with 32-bit accumulator
│   │   └── seven_seg_controller.v # Multi-digit 7-segment display controller
│   ├── constraints/           # Physical pin and timing constraints
│   │   └── boolean_npu.xdc    # XDC mapping for Real Digital Spartan-7 Boolean Board
│   ├── sim/                   # Verification testbenches
│   │   ├── tb_picorv32_npu.v  # Full SoC testbench with live CPU & UART decode
│   │   └── tb_npu.v           # Standalone cycle-accurate NPU testbench
│   ├── mem/                   # Memory initialization tables ($readmemh)
│   │   ├── weights_l1.mem     # Layer 1 weights (12,544 bytes)
│   │   ├── biases_l1.mem      # Layer 1 biases (16 words)
│   │   ├── weights_l2.mem     # Layer 2 weights (160 bytes)
│   │   ├── biases_l2.mem      # Layer 2 biases (10 words)
│   │   └── firmware.hex       # Compiled RISC-V bootloader & benchmark image
│   └── scripts/               # Vivado automation Tcl scripts
│       ├── build_bitstream.tcl# Automated synthesis, place, route, and bitgen
│       ├── program_board.tcl  # JTAG board flashing script
│       └── create_and_run_vivado_project.tcl # Vivado GUI project creator
│
├── c/                         # RISC-V Bare-Metal C Firmware, Bootloader & Linker
│   ├── main.c                 # Benchmark firmware, NPU driver & interactive UART loop
│   ├── start.S                # Assembly reset vector, trap handler & stack initialization
│   ├── sections.lds           # Linker script mapping 32 KB ROM & 8 KB RAM
│   ├── mnist_model_data.h     # INT8 model parameters in C header format
│   ├── Makefile               # Automated build script for riscv64-unknown-elf-gcc
│   ├── firmware.elf           # Compiled RISC-V ELF
│   ├── firmware.bin           # Flat binary machine code
│   └── firmware.hex           # Verilog $readmemh memory file
│
└── python/                    # Machine Learning, Quantization & Touch GUI
    ├── train_mnist_int8.py    # PyTorch training, INT8 quantization & memory exporter
    ├── touch_board_bridge.py  # Live touchscreen/mouse GUI & UART serial bridge
    └── requirements.txt       # Python package dependencies
```

---

## 📌 Hardware Pinout (Boolean Board)

Targeted for the **Real Digital Spartan-7 Boolean Board (`xc7s50csga324-1`)**:

| Function | Board Net | FPGA Pin | I/O Standard | Description |
| :--- | :--- | :---: | :---: | :--- |
| **System Clock** | `CLK100MHZ` | **`F14`** | `LVCMOS33` | 100 MHz Onboard Oscillator |
| **Master Reset** | `BTN0` | **`J2`** | `LVCMOS33` | Active-Low Reset Pushbutton |
| **UART RX** | `UART_TXD_IN` | **`V12`** | `LVCMOS33` | USB-UART Serial RX (from Host) |
| **UART TX** | `UART_RXD_OUT` | **`U11`** | `LVCMOS33` | USB-UART Serial TX (to Host) |
| **7-Seg Anode 0** | `D0_a[0]` | **`D5`** | `LVCMOS33` | Digit 0 Anode (Active-Low) |
| **7-Seg Anode 1** | `D0_a[1]` | **`C4`** | `LVCMOS33` | Digit 1 Anode (Active-Low) |
| **7-Seg Anode 2** | `D0_a[2]` | **`C7`** | `LVCMOS33` | Digit 2 Anode (Active-Low) |
| **7-Seg Anode 3** | `D0_a[3]` | **`A8`** | `LVCMOS33` | Digit 3 Anode (Active-Low) |
| **7-Seg Cathodes** | `D0_seg[6:0]` | **`B5, D6, A7, B7, A5, C5, D7`** | `LVCMOS33` | Segments G through A (Active-Low) |
| **User LEDs** | `LED[3:0]` | **`G1, G2, F1, F2`** | `LVCMOS33` | Binary Predicted Digit (0-9) |
| **Status LEDs** | `LED[6:4]` | **`E1, E2, E3`** | `LVCMOS33` | Heartbeat, NPU Done, NPU Busy |

---

## ⚡Project Implementation Guide

### 1. Train and Export INT8 Model
### 2. Build RISC-V Firmware
### 3. Build FPGA Bitstream 
### 4. Program Spartan-7 Boolean Board
### 5. Launch Live Touch Drawing Interface

## Real-Time Applications

- **Handwritten Digit Recognition:** Recognizes handwritten digits in digital forms, tablets, and data-entry systems.
- **Automatic Meter Reading:** Identifies numerical readings on electricity and water meters.
- **Edge AI Devices:** Performs AI inference locally on embedded devices without cloud connectivity.
- **Industrial Inspection:** Recognizes numerical labels and markings in manufacturing systems.
- **Smart Document Processing:** Extracts handwritten digits from forms, receipts, and applications.



<div align="center">
Made for Edge AI & Reconfigurable Computing • Real Digital Spartan-7 Boolean Platform
</div>
