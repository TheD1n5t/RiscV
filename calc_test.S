.section .text
.global _start

_start:
    li s0, 0x40002000

    # Beispielrechnung: 23 * 17 = 391
    li t0, 23
    li t1, 17
    mul t2, t0, t1

    mv a0, t2
    jal ra, print_uint

    li t0, 13
    sw t0, 0(s0)
    jal ra, delay

    li t0, 10
    sw t0, 0(s0)

done:
    j done


# a0 = unsigned value 0..9999
print_uint:
    li t0, 1000
    li t1, 0              # already_printed

    # Tausender
    li t2, 0
pu_1000:
    blt a0, t0, pu_100
    addi t2, t2, 1
    sub a0, a0, t0
    j pu_1000

pu_100:
    beqz t2, pu_100_skip
    addi t3, t2, 48
    sw t3, 0(s0)
    jal ra, delay
    li t1, 1
pu_100_skip:

    li t0, 100
    li t2, 0
pu_100_loop:
    blt a0, t0, pu_10
    addi t2, t2, 1
    sub a0, a0, t0
    j pu_100_loop

pu_10:
    beqz t1, pu_100_cond
    j pu_100_print
pu_100_cond:
    beqz t2, pu_10_setup
pu_100_print:
    addi t3, t2, 48
    sw t3, 0(s0)
    jal ra, delay
    li t1, 1

pu_10_setup:
    li t0, 10
    li t2, 0
pu_10_loop:
    blt a0, t0, pu_1
    addi t2, t2, 1
    sub a0, a0, t0
    j pu_10_loop

pu_1:
    beqz t1, pu_10_cond
    j pu_10_print
pu_10_cond:
    beqz t2, pu_1_print
pu_10_print:
    addi t3, t2, 48
    sw t3, 0(s0)
    jal ra, delay
    li t1, 1

pu_1_print:
    addi t3, a0, 48
    sw t3, 0(s0)
    jal ra, delay
    ret


delay:
    li t6, 12000
delay_loop:
    addi t6, t6, -1
    bnez t6, delay_loop
    ret