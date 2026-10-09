/* ============================================================================
 * sections.lds - Linker script for PicoRV32 SoC with 32KB ROM and 8KB RAM
 * ============================================================================ */

MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    RAM (rwx) : ORIGIN = 0x10000000, LENGTH = 8K
}

ENTRY(_start)

SECTIONS
{
    .text :
    {
        . = ALIGN(4);
        *(.text.start)
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
        _etext = .;
    } > ROM

    _sidata = LOADADDR(.data);

    .data :
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        *(.sdata*)
        . = ALIGN(4);
        _edata = .;
    } > RAM AT > ROM

    .bss (NOLOAD) :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    _stack_top = ORIGIN(RAM) + LENGTH(RAM);

    /DISCARD/ :
    {
        *(.note*)
        *(.comment*)
        *(.riscv.attributes)
    }
}
