.section .text
.global _start

_start:
    li sp, 0x00001000
    li s0, 0x40002000      # UART MMIO base

    li s1, 0               # a = F(n)
    li s2, 1               # b = F(n+1)
    li s3, 16              # Anzahl Werte

fib_loop:
    mv a0, s1
    jal ra, print_uint

    li t0, '\r'
    sw t0, 0(s0)
    jal ra, delay

    li t0, '\n'
    sw t0, 0(s0)
    jal ra, delay

    add t1, s1, s2         # next = a + b
    mv s1, s2              # a = b
    mv s2, t1              # b = next

    addi s3, s3, -1
    bnez s3, fib_loop

done:
    j done


# a0 = unsigned Zahl 0..9999
print_uint:
    addi sp, sp, -4
    sw ra, 0(sp)

    li t0, 1000
    li t1, 0               # printed flag
    li t2, 0               # digit counter

thousands_loop:
    blt a0, t0, hundreds_setup
    addi t2, t2, 1
    sub a0, a0, t0
    j thousands_loop

hundreds_setup:
    beqz t2, hundreds_calc
    addi t3, t2, 48
    sw t3, 0(s0)
    jal ra, delay
    li t1, 1

hundreds_calc:
    li t0, 100
    li t2, 0

hundreds_loop:
    blt a0, t0, tens_setup
    addi t2, t2, 1
    sub a0, a0, t0
    j hundreds_loop

tens_setup:
    beqz t1, maybe_skip_hundreds
    j print_hundreds

maybe_skip_hundreds:
    beqz t2, tens_calc

print_hundreds:
    addi t3, t2, 48
    sw t3, 0(s0)
    jal ra, delay
    li t1, 1

tens_calc:
    li t0, 10
    li t2, 0

tens_loop:
    blt a0, t0, ones_setup
    addi t2, t2, 1
    sub a0, a0, t0
    j tens_loop

ones_setup:
    beqz t1, maybe_skip_tens
    j print_tens

maybe_skip_tens:
    beqz t2, print_ones

print_tens:
    addi t3, t2, 48
    sw t3, 0(s0)
    jal ra, delay
    li t1, 1

print_ones:
    addi t3, a0, 48
    sw t3, 0(s0)
    jal ra, delay

    lw ra, 0(sp)
    addi sp, sp, 4
    ret


delay:
    li t6, 12000
delay_loop:
    addi t6, t6, -1
    bnez t6, delay_loop
    ret