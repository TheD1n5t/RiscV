.section .text
.global _start
.extern __stack_top

_start:
    la sp, __stack_top

    li x31, 0x00000FFC
    li x30, 0x00000FF8
    li x29, 0x00000100

    li x5, 0
    li x6, 96
    li x7, 0x2468ACE1
    li x8, 0x11223344
    sw x8, 0(x29)

loop_body:
    lw x8, 0(x29)
    andi x9, x5, 3
    beq x9, x0, case0

    li x10, 1
    beq x9, x10, case1

    li x10, 2
    beq x9, x10, case2

case3:
    xor x7, x7, x8
    addi x7, x7, 0x77
    j after_case

case2:
    add x7, x7, x8
    xori x7, x7, 0x155
    j after_case

case1:
    sub x7, x7, x8
    xori x7, x7, 0x0AA
    j after_case

case0:
    add x7, x7, x5
    xor x7, x7, x8

after_case:
    andi x10, x7, 1
    beq x10, x0, even_path

odd_path:
    slli x7, x7, 1
    xori x7, x7, 0x321
    j path_done

even_path:
    srli x7, x7, 1
    xori x7, x7, 0x123

path_done:
    sw x7, 4(x29)
    lw x11, 4(x29)
    bne x11, x7, fail

    add x12, x8, x5
    sw x12, 0(x29)

    addi x5, x5, 1
    blt x5, x6, loop_body

    li x13, 0xDCC4D493
    sw x7, 0(x30)
    bne x7, x13, fail

    li x14, 1
    sw x14, 0(x31)

pass:
    j pass

fail:
    li x14, 2
    sw x14, 0(x31)

fail_loop:
    j fail_loop
