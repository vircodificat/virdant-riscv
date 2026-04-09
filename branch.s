.section .text
.globl _start

_start:
    li t0, 1
    bnez t0, exit

loop:
    jal loop

exit:
    ebreak
