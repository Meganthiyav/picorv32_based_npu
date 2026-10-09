# ============================================================================
# start.S - Startup code for PicoRV32 RISC-V CPU
# ============================================================================

    .section .text.start
    .global _start
    .type _start, @function

_start:
    # Set up stack pointer to top of RAM (0x10002000)
    la sp, _stack_top

    # Zero-initialize the .bss section
    la t0, _sbss
    la t1, _ebss
bss_zero_loop:
    bge t0, t1, bss_zero_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_zero_loop
bss_zero_done:

    # Copy .data section from ROM to RAM
    la t0, _sdata
    la t1, _edata
    la t2, _sidata
data_copy_loop:
    bge t0, t1, data_copy_done
    lw t3, 0(t2)
    sw t3, 0(t0)
    addi t0, t0, 4
    addi t2, t2, 4
    j data_copy_loop
data_copy_done:

    # Jump to C main function
    jal main

    # Infinite loop if main returns
hang:
    j hang
