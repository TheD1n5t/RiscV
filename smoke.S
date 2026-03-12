.section .text
.global _start

_start:
    li t0, 0x40002000

    li t1, 'H'
    sw t1, 0(t0)
    jal ra, delay

    li t1, 'i'
    sw t1, 0(t0)
    jal ra, delay

    li t1, '\r'
    sw t1, 0(t0)
    jal ra, delay

    li t1, '\n'
    sw t1, 0(t0)

done:
    j done

delay:
    li t2, 12000
delay_loop:
    addi t2, t2, -1
    bnez t2, delay_loop
    ret