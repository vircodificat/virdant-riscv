# sw/mandelbrot/main.s — ASCII Mandelbrot renderer for virdant-riscv.
#
# Renders an 80x24 ASCII Mandelbrot set over the UART, then halts (a0=0,
# EBREAK — the virt simulator exits with that code).
#
# Pure RV32I: the core has no M extension, so multiplication is done in
# software with a classic 32-iteration shift-and-add (mul32), and the
# fixed-point math uses Q4.12 (scale = 4096, range ~[-8, 8)).
#
# Q4.12 is enough headroom: values entering a multiply satisfy |z| <= 2
# (the escape check runs first), so products stay under 2^31 and never
# overflow the 32-bit low word that mul32 produces.

.section .text
.globl _start

.equ UART_BASE, 0x40000000
.equ UART_LSR,  0x40000004
.equ LSR_TEMT,  (1 << 5)

.equ SCALE,   4096            # Q4.12 fixed point
.equ FOUR,    (4 * SCALE)     # escape threshold: |z|^2 > 4.0
.equ MAXITER, 16
.equ COLS,    80
.equ ROWS,    24
.equ XSTEP,   130             # (0.5 + 2.0) * SCALE / 79 ≈ 129.6
.equ YSTEP,   356             # 2.0 * SCALE / 23 ≈ 356.2
.equ X0,      -8192           # left edge: -2.0
.equ Y0,      4096            # top edge: +1.0
.equ RAMPLEN, 10

_start:
    lui  sp, 0x80001         # sp = 0x80001000 (above the loaded image)

    la   a0, banner
    jal  puts

    li   s0, 0               # s0 = row

row_loop:
    # cy = Y0 - row * YSTEP  (render top row first)
    li   a1, YSTEP
    mv   a0, s0
    call mul32               # a0 = row * YSTEP
    li   s1, Y0
    sub  s1, s1, a0          # s1 = cy

    li   s2, 0               # s2 = col

col_loop:
    # cx = X0 + col * XSTEP
    li   a1, XSTEP
    mv   a0, s2
    call mul32               # a0 = col * XSTEP
    li   s3, X0
    add  s3, s3, a0          # s3 = cx

    li   s4, 0               # s4 = zx
    li   s5, 0               # s5 = zy
    li   s6, MAXITER         # s6 = iterations remaining

iter_loop:
    # zx2 = fp_mul(zx, zx)
    mv   a0, s4
    mv   a1, s4
    call fp_mul
    mv   s7, a0              # s7 = zx^2

    # zy2 = fp_mul(zy, zy)
    mv   a0, s5
    mv   a1, s5
    call fp_mul
    mv   s8, a0              # s8 = zy^2

    # Escape if zx2 + zy2 > 4.0
    add  t0, s7, s8
    li   t1, FOUR
    bgt  t0, t1, escaped

    # zy = fp_mul(zx, zy) * 2 + cy
    mv   a0, s4
    mv   a1, s5
    call fp_mul
    slli a0, a0, 1
    add  s5, a0, s1

    # zx = zx2 - zy2 + cx
    sub  s4, s7, s8
    add  s4, s4, s3

    addi s6, s6, -1
    bnez s6, iter_loop

escaped:
    # char index = MAXITER - s6 (iterations completed), clamped to ramp
    li   t0, MAXITER
    sub  t0, t0, s6
    li   t1, RAMPLEN - 1
    ble  t0, t1, 1f
    li   t0, RAMPLEN - 1
1:  la   t2, ramp
    add  t2, t2, t0
    lbu  a0, 0(t2)
    jal  putc

    addi s2, s2, 1
    li   t0, COLS
    blt  s2, t0, col_loop

    li   a0, '\n'
    jal  putc
    li   a0, '\r'
    jal  putc

    addi s0, s0, 1
    li   t0, ROWS
    blt  s0, t0, row_loop

    la   a0, done_str
    jal  puts

    li   a0, 0               # exit code 0
    ebreak

# ── putc: write the byte in a0 to the UART THR ──────────────────────
# Polls LSR.TEMT first.  Clobbers t0-t2; preserves a1 and t3.
putc:
    li   t0, UART_BASE
    li   t1, UART_LSR
1:  lw   t2, 0(t1)
    andi t2, t2, LSR_TEMT
    beqz t2, 1b
    sw   a0, 0(t0)
    ret

# ── puts: write the NUL-terminated string at a0 ─────────────────────
# Clobbers t0-t3 and a0.  Saves ra: the jal putc below overwrites it.
puts:
    addi sp, sp, -4
    sw   ra, 0(sp)
    mv   t3, a0
1:  lbu  a0, 0(t3)
    beqz a0, 2f
    jal  putc
    addi t3, t3, 1
    j    1b
2:  lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# ── mul32: unsigned 32x32 -> low 32 bits of the product ─────────────
# a0 * a1 -> a0.  Shift-and-add, 32 iterations.  Clobbers t0-t3 and a0;
# preserves a1 and ra.  The low 32 bits of the unsigned product equal
# the low 32 bits of the signed product, and our operands never overflow
# 32 bits signed, so this serves as a signed multiply for Q4.12.
mul32:
    li   t0, 32
    mv   t1, a0              # multiplicand copy, shifted left each step
    mv   t2, a1              # multiplier copy, shifted right each step
    li   a0, 0               # accumulator / result
1:  andi t3, t2, 1
    beqz t3, 2f
    add  a0, a0, t1
2:  srli t2, t2, 1
    slli t1, t1, 1
    addi t0, t0, -1
    bnez t0, 1b
    ret

# ── fp_mul: Q4.12 fixed-point multiply ──────────────────────────────
# a0 * a1 -> a0 = (a0 * a1) >> 12 (arithmetic shift).  Clobbers ra, a0.
fp_mul:
    addi sp, sp, -4
    sw   ra, 0(sp)
    call mul32
    srai a0, a0, 12
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

.section .rodata
banner:
    .ascii "MANDELBROT RV32I\n\r"
    .byte 0
done_str:
    .ascii "\n\rDONE\n\r"
    .byte 0
ramp:
    .ascii " .:-=+*#%@"
    .byte 0
