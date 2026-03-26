_start:
    li sp, 0x1000
    li t0, 44
    li t1, 89
    li ra, 1
    add ra, ra, ra
    sw t1, 0(sp)
    lw t2, 0(sp)
    beq t1, t2, _start
