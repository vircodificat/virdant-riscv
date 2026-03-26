.section .text
.globl _start

_start:
    li t0, 10        # loop counter

loop:
    addi t0, t0, -1 # decrement counter
    bnez t0, loop   # if t0 != 0, continue looping

    ebreak          # stop execution / trigger debugger
