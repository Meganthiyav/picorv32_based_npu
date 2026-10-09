# RISC-V C Firmware & System Software

This folder contains the complete bare-metal firmware, startup routines, memory layout linker script, and drivers running on the **PicoRV32 RISC-V RV32I** soft-core processor.

---

## 📂 File Organization

| File | Description |
| :--- | :--- |
| **[`main.c`](file:///c:/Users/Lenovo/OneDrive/Desktop/Makeathon/PICORV_32_NPU/c/main.c)** | Application firmware: CPU baseline benchmark, NPU accelerator driver, 7-segment display control, and live UART ingestion loop. |
| **[`start.S`](file:///c:/Users/Lenovo/OneDrive/Desktop/Makeathon/PICORV_32_NPU/c/start.S)** | Assembly reset vector, trap handler, and stack pointer initialization (`sp = 0x10002000`). |
| **[`sections.lds`](file:///c:/Users/Lenovo/OneDrive/Desktop/Makeathon/PICORV_32_NPU/c/sections.lds)** | GNU Linker script mapping 32 KB Boot ROM (`0x00000000`) and 8 KB Application RAM (`0x10000000`). |
| **[`mnist_model_data.h`](file:///c:/Users/Lenovo/OneDrive/Desktop/Makeathon/PICORV_32_NPU/c/mnist_model_data.h)** | C header containing INT8 model weights, biases, calibration shifts, and test vectors. |
| **[`Makefile`](file:///c:/Users/Lenovo/OneDrive/Desktop/Makeathon/PICORV_32_NPU/c/Makefile)** | Automated compilation script targeting `riscv64-unknown-elf-gcc`. |
| **`firmware.elf`** | Compiled RISC-V ELF binary executable. |
| **`firmware.bin`** | Raw flat binary machine code. |
| **`firmware.hex`** | 32-bit little-endian hexadecimal memory initialization image for Verilog `$readmemh`. |

---

## 🗺️ Memory Map & Hardware Registers

All peripherals are memory-mapped onto the native 32-bit bus of the PicoRV32 processor:

```
0x0000_0000 ───┬────────────────────────────────────────── Boot ROM (32 KB BRAM)
               │ (Executes firmware.hex directly on reset)
0x0000_7FFF ───┴──────────────────────────────────────────
0x1000_0000 ───┬────────────────────────────────────────── Application RAM (8 KB BRAM)
               │ (.data, .bss, Stack @ 0x1000_2000)
0x1000_1FFF ───┴──────────────────────────────────────────
0x2000_0000 ───┬── UART DATA Register   [7:0] Data Byte
0x2000_0004 ───┴── UART STATUS Register [0] TX Busy, [1] RX Ready
0x3000_0000 ───┬── NPU CTRL Register    [0] Start Full, [1] Start L1, [2] Start L2
0x3000_0004 ───┼── NPU STATUS Register  [0] Busy, [1] Done
0x3000_0008 ───┼── NPU CONFIG Register  [4:0] Activation Shift (Default: 10 bits)
0x3000_000C ───┼── NPU PRED_DIGIT       [3:0] Winning Digit (0-9), [7] Valid
0x3000_0010 ───┼── NPU CYCLE_COUNT      [31:0] Hardware Execution Latency
0x3000_0014 ───┼── SSEG CTRL Register   [31] Enable, [19:16] Anode Mask, [15:0] Nibbles
0x3000_0018 ───┼── LED Register         [15:0] On-board User LEDs
0x3000_0020 ───┼── NPU Score Class 0    [31:0] Signed INT32 Logit
...            │   ...
0x3000_0044 ───┼── NPU Score Class 9    [31:0] Signed INT32 Logit
0x3000_0800 ───┴── Dual-Port Image BRAM [784 Bytes] 28x28 INT8 Input Pixels
```

---

## ⚡ How to Compile

Using the RISC-V GCC toolchain:
```bash
riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -nostdlib -T sections.lds -o firmware.elf start.S main.c -lgcc
riscv64-unknown-elf-objcopy -O binary firmware.elf firmware.bin
python -c "
with open('firmware.bin', 'rb') as f: data = f.read()
while len(data) % 4 != 0: data += b'\x00'
with open('firmware.hex', 'w') as f:
    for i in range(0, len(data), 4):
        w = data[i] | (data[i+1]<<8) | (data[i+2]<<16) | (data[i+3]<<24)
        f.write(f'{w:08x}\n')
"
```
Or simply run:
```bash
make
```
