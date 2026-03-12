.section .text
.global _start
.extern main
.extern __bss_start
.extern __bss_end
.extern __stack_top

_start:
    la sp, __stack_top

    la t0, __bss_start
    la t1, __bss_end

clear_bss:
    beq t0, t1, call_main
    sw zero, 0(t0)
    addi t0, t0, 4
    j clear_bss

call_main:
    call main

hang:
    j hang