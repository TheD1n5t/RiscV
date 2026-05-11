.section .text
.global _start
.extern __stack_top

_start:
    la sp, __stack_top

    li x31, 0x00000FFC
    li x30, 0x00000FF8
    li x29, 0x00000100

    li x4, 0x12345678
    sw x4, 0(x29)

    li x2, 0
    li x3, 256
    li x10, 0x13579BDF

loop_body:
    lw x4, 0(x29)
    xor x5, x4, x10
    add x6, x5, x2
    slli x7, x6, 3
    srli x8, x6, 2
    xor x9, x7, x8
    add x10, x10, x9
    xori x10, x10, 0x5A5
    addi x2, x2, 1
    addi x4, x4, 0x111
    xor x4, x4, x2
    sw x4, 0(x29)
    blt x2, x3, loop_body

    li x11, 0xD146879D
    sw x10, 0(x30)
    bne x10, x11, fail

    li x12, 1
    sw x12, 0(x31)

pass:
    j pass

fail:
    li x12, 2
    sw x12, 0(x31)

fail_loop:
    j fail_loop
