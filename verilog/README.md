# Verilog Hardware & FPGA Accelerator Architecture

This directory houses all Verilog 2001 hardware description modules (RTL), physical XDC constraints for the **Real Digital Spartan-7 Boolean Board (`xc7s50csga324-1`)**, verification testbenches, and Vivado automation Tcl scripts.

---

## 📂 Subdirectory Overview

```
verilog/
├── rtl/               # Synthesizable RTL source files
│   ├── picorv32_npu_top.v      # SoC Top module: interconnects CPU, ROM, RAM, BRAM, NPU, SSEG, UART
│   ├── picorv32.v              # PicoRV32 RISC-V RV32I Processor core by Claire Wolf
│   ├── npu_controller.v        # NPU FSM, address generator, ReLU requantizer & Argmax engine
│   ├── npu_mac.v               # Signed INT8 x INT8 MAC arithmetic unit with 32-bit accumulator
│   └── seven_seg_controller.v  # Clock-divided (~1.5 kHz) active-low common-anode display driver
├── constraints/       # FPGA timing and pin constraints
│   └── boolean_npu.xdc         # Physical pinout mapping for Boolean Board (100 MHz, 7-Seg, LEDs, UART)
├── sim/               # Functional verification testbenches
│   ├── tb_picorv32_npu.v       # Full SoC testbench with live CPU execution and UART monitor
│   └── tb_npu.v                # Standalone cycle-accurate NPU testbench
├── mem/               # Initial memory contents ($readmemh hex files)
│   ├── weights_l1.mem          # Layer 1 weights (12,544 bytes)
│   ├── biases_l1.mem           # Layer 1 biases (16 INT32 words)
│   ├── weights_l2.mem          # Layer 2 weights (160 bytes)
│   ├── biases_l2.mem           # Layer 2 biases (10 INT32 words)
│   ├── firmware.hex            # Bootloader & benchmark RISC-V binary image
│   └── test_img_digit_0..9.mem # Golden MNIST verification test vectors
└── scripts/           # Vivado automation scripts
    ├── build_bitstream.tcl     # Batch synthesis, placement, routing, and bitstream generation
    ├── program_board.tcl       # JTAG hardware server programmer
    └── create_and_run_vivado_project.tcl # Complete Vivado GUI project generator
```

---

## ⚡ Accelerator Hardware Architecture

The custom INT8 NPU peripheral consists of:

```
                      +-----------------------------+
                      |       NPU Controller        |
                      |  (Pipelined Control FSM)    |
                      +--------------+--------------+
                                     |
               +---------------------+---------------------+
               |                                           |
               v                                           v
     +-------------------+                       +-------------------+
     | Dual-Port Image   |                       | Weight & Bias     |
     | BRAM (784 x 8-bit)|                       | BRAMs (Synchronous|
     +---------+---------+                       +---------+---------+
               |                                           |
               +---------------------+---------------------+
                                     |
                                     v
                           +-------------------+
                           |    npu_mac.v      |
                           | Signed INT8 MAC   |
                           | 32-bit Accumulator|
                           +---------+---------+
                                     |
                                     v
                           +-------------------+
                           | ReLU Requantizer  |
                           | (>> 10-bit Shift) |
                           +---------+---------+
                                     |
                                     v
                           +-------------------+
                           |   Argmax Engine   |
                           |  (Digits 0 to 9)  |
                           +-------------------+
```

### 1. Arithmetic Pipeline
- **Multiplier:** Signed $8\text{-bit} \times \text{signed } 8\text{-bit} \to \text{signed } 16\text{-bit product}$.
- **Accumulator:** 32-bit signed accumulator initialized with the layer bias before each neuron calculation:
  $$\text{ACC} \leftarrow \text{Bias}_j + \sum_{i} X_i \times W_{ji}$$
- **Requantization:** ReLU zeroes out negative sums, and a parameterized arithmetic right shift (default: 10 bits) rescales 32-bit sums back into $[0, 127]$ INT8 activations.

### 2. Execution Timing & Latency
- **Layer 1:** 16 neurons $\times$ 784 MAC operations = 12,544 cycles
- **Layer 2:** 10 neurons $\times$ 16 MAC operations = 160 cycles
- **FSM Overhead & Argmax:** ~80 cycles
- **Total Hardware Latency:** Exactly **12,784 clock cycles** (**127.8 microseconds** at 100 MHz).

---

## 📊 FPGA Resource Utilization on Spartan-7 (XC7S50)

| Resource | Used | Available | Utilization % |
| :--- | :---: | :---: | :---: |
| **LUTs (Logic)** | 6,110 | 32,600 | **18.7%** |
| **Flip-Flops (FF)** | 1,733 | 65,200 | **2.6%** |
| **Block RAM (RAMB36)** | 4 | 75 | **5.3%** |
| **DSP48 Slices** | 0 | 120 | **0.0% (Pure Logic MAC)** |
| **Worst Negative Slack (WNS)** | **+0.919 ns** | 0.000 ns | **Timing Met @ 100 MHz** |
