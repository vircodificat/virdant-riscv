.section .text
.globl _start

_start:
    li t0, 4
    li t1, 0

loop:
    addi t0, t0, -1 # decrement counter
    bnez t0, loop   # if t0 != 0, continue looping

    addi t1, t1, 1
    li t0, 4
    jal loop

    ebreak          # stop execution / trigger debugger
