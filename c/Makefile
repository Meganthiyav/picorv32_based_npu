# ==============================================================================
# Makefile for PicoRV32 INT8 NPU Firmware
# Target: RISC-V RV32I Soft Core
# Toolchain: riscv64-unknown-elf-gcc
# ==============================================================================

CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump
PYTHON  = python

CFLAGS  = -march=rv32i -mabi=ilp32 -O2 -nostdlib -Wall -Wextra
LDFLAGS = -T sections.lds

TARGET  = firmware

all: $(TARGET).hex $(TARGET).bin

$(TARGET).elf: start.S main.c mnist_model_data.h sections.lds
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S main.c -lgcc
	@echo "Built $@"

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@
	@echo "Generated $@"

$(TARGET).hex: $(TARGET).bin
	$(PYTHON) -c "with open('$<', 'rb') as f: data = f.read()\nwhile len(data) % 4 != 0: data += b'\x00'\nwith open('$@', 'w') as f:\n    for i in range(0, len(data), 4):\n        w = data[i] | (data[i+1]<<8) | (data[i+2]<<16) | (data[i+3]<<24)\n        f.write(f'{w:08x}\n')"
	@echo "Generated Verilog \$$readmemh $@ with $$(cat $@ | wc -l) words"

disasm: $(TARGET).elf
	$(OBJDUMP) -d $< > $(TARGET).asm

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).hex $(TARGET).asm

.PHONY: all clean disasm
