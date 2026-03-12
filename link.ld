ENTRY(_start)

MEMORY
{
  IMEM (rx)   : ORIGIN = 0x00000000, LENGTH = 16K
  DMEM (rwx)  : ORIGIN = 0x00000000, LENGTH = 4K
  LOAD (r)    : ORIGIN = 0x00100000, LENGTH = 32K
}

SECTIONS
{
  .text : {
    . = ALIGN(4);
    *(.text*)
    . = ALIGN(4);
  } > IMEM

  .rodata : {
    . = ALIGN(4);
    *(.rodata*)
    *(.srodata*)
    . = ALIGN(4);
  } > DMEM AT > LOAD

  .data : {
    . = ALIGN(4);
    *(.data*)
    *(.sdata*)
    . = ALIGN(4);
  } > DMEM AT > LOAD

  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  } > DMEM

  __stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
}