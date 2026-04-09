.section .text
.globl _start

_start:
    li t0, 4      # 0x00
    li t1, 0      # 0x04

loop:
    addi t0, t0, -1 # 0x08
    bnez t0, loop   # 0x0c

    addi t1, t1, 1  # 0x10
    jal loop        # 0x14

    ebreak          # 0x1c
