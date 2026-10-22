# sw/donut/main.s — spinning ASCII donut for virdant-riscv.
#
# Fixed-point port of a1k0n's famous donut.c: no floats, no M extension.
# All multiplies are 16x16 shift-and-add (mul16), all trig comes from a
# 256-entry Q4.12 sine table, and the inner render loop is pure table
# lookups — no calls, no multiplies.
#
# Math: expand a1k0n's formulas with product-to-sum identities.  With
# ring angle alpha = ii*d, tube angle beta = jj*d (same table step d),
# every per-point quantity is  const_i + const_j + T[ii+jj] + T[ii-jj]:
#
#   x'' = TX[p] + TX[q] + XI + XS[jj]    p = ii+jj, q = ii-jj (mod 256)
#   y'' = TY[p] + TY[q] + YI + YS[jj]
#   z'  = TZ[p] + TZ[q] + ZI + ZS[jj]    (smaller z' = closer to viewer)
#   L   = TN[p] + TN[q] + NS[jj]         (surface normal . light)
#
# Per-frame tables (C[k] = cos, S[k] = sin, e=sinA g=cosA n=sinB m=cosB,
# gn = g*n, gm = g*m, en = e*n, em = e*m, V = em-g, W = gm+e):
#   TX[k] = ( m*C[k] - gn*S[k]) / 2     TY[k] = ( n*C[k] + gm*S[k]) / 2
#   TZ[k] = ( e*S[k]) / 2               TN[k] = -( W*S[k] + n*C[k]) / 2
#   XS[k] = en*S[k]   YS[k] = -em*S[k]  ZS[k] = g*S[k]   NS[k] = V*S[k]
# Per-i terms:  XI = 2(l*m - c*gn)   YI = 2(l*n + c*gm)   ZI = 2(e*c)
# (l = cos alpha, c = sin alpha; all values Q4.12.)
#
# Screen: 80x26, halfword z-buffer, background ' ', ramp ".,-~:;=!*#$@".
# Projection (terminal cells ~2:1 tall, so y-scale = x-scale / 2):
#   sx = 40 + (8*x'') >> 12        sy = 13 + (4*y'') >> 12
# Plots if z' < zbuf[o]; char index = clamp(L >> 9, 0, 11).
# Spins forever: A += 2, B += 1 table indices per frame.  Ctrl+C exits.

.section .text
.globl _start

.equ UART_BASE, 0x40000000
.equ UART_LSR,  0x40000004
.equ LSR_TEMT,  (1 << 5)

.equ TBASE,  0x80002000        # 4 tables x 256 halfwords (TX TY TZ TN)
.equ TBASE2, 0x80002800        # 4 tables x 256 halfwords (XS YS ZS NS)
.equ ZBUF,   0x80003000        # 2080 halfwords
.equ CHARS,  0x80004040        # 2080 bytes
.equ COLS,   80
.equ ROWS,   26
.equ CELLS,  2080

# Stack frame scalars (Q4.12), offsets from sp (frame = 52 bytes)
.equ E,  0                     # sinA
.equ G,  4                     # cosA
.equ M,  8                     # cosB
.equ N,  12                    # sinB
.equ GN, 16                    # cosA*sinB
.equ GM, 20                    # cosA*cosB
.equ EN, 24                    # sinA*sinB
.equ EM, 28                    # sinA*cosB
.equ V,  32                    # em - cosA
.equ W,  36                    # gm + sinA
.equ L_ST, 40                  # per-i stash: cos(alpha)
.equ C_ST, 44                  # per-i stash: sin(alpha)
.equ SCR, 48                   # product scratch

_start:
    lui  sp, 0x80001          # sp = 0x80001000
    addi sp, sp, -52          # scalar frame (persists across frames)

    la   a0, banner
    jal  puts

    li   s9, 24               # A angle index
    li   s10, 48              # B angle index
    li   s8, TBASE
    li   s5, TBASE2
    li   s6, ZBUF
    li   s7, CHARS

# ── Frame loop ──────────────────────────────────────────────────────
frame:
    # ── Clear z-buffer (0x7FFF) and char buffer (' ') ────────────────
    li   t0, 0x7fff
    li   t1, CELLS
    mv   t2, s6
1:  sh   t0, 0(t2)
    addi t2, t2, 2
    addi t1, t1, -1
    bnez t1, 1b
    li   t0, 32
    li   t1, CELLS
    mv   t2, s7
2:  sb   t0, 0(t2)
    addi t2, t2, 1
    addi t1, t1, -1
    bnez t1, 2b

    # ── sinA/cosA/sinB/cosB from table indices s9 (A), s10 (B) ──────
    la   t0, sintab
    slli t1, s9, 1
    add  t1, t1, t0
    lh   t1, 0(t1)
    sw   t1, E(sp)            # e = sinA
    addi t1, s9, 64
    andi t1, t1, 0xff
    slli t1, t1, 1
    add  t1, t1, t0
    lh   t1, 0(t1)
    sw   t1, G(sp)            # g = cosA
    slli t1, s10, 1
    add  t1, t1, t0
    lh   t1, 0(t1)
    sw   t1, N(sp)            # n = sinB
    addi t1, s10, 64
    andi t1, t1, 0xff
    slli t1, t1, 1
    add  t1, t1, t0
    lh   t1, 0(t1)
    sw   t1, M(sp)            # m = cosB

    # ── Derived scalars ──────────────────────────────────────────────
    lw   a0, G(sp)
    lw   a1, N(sp)
    call fp_mul
    sw   a0, GN(sp)
    lw   a0, G(sp)
    lw   a1, M(sp)
    call fp_mul
    sw   a0, GM(sp)
    lw   a0, E(sp)
    lw   a1, N(sp)
    call fp_mul
    sw   a0, EN(sp)
    lw   a0, E(sp)
    lw   a1, M(sp)
    call fp_mul
    sw   a0, EM(sp)
    lw   t0, G(sp)
    sub  t0, a0, t0          # em - g
    sw   t0, V(sp)
    lw   t0, GM(sp)
    lw   t1, E(sp)
    add  t0, t0, t1          # gm + e
    sw   t0, W(sp)

    # ── Build the 8 per-frame tables (256 entries each) ──────────────
    # s2 = S value, s3 = C value, s0 = k
    li   s0, 0
tbl_loop:
    la   t0, sintab
    slli t1, s0, 1
    add  t2, t0, t1
    lh   s2, 0(t2)            # S = sin(k)
    addi t1, s0, 64
    andi t1, t1, 0xff
    slli t1, t1, 1
    add  t1, t1, t0
    lh   s3, 0(t1)            # C = cos(k)
    # TX[k] = (m*C - gn*S) >> 1
    mv   a1, s3
    lw   a0, M(sp)
    call fp_mul
    sw   a0, SCR(sp)
    mv   a1, s2
    lw   a0, GN(sp)
    call fp_mul
    lw   t5, SCR(sp)
    sub  t5, t5, a0
    srai t5, t5, 1
    slli t6, s0, 1
    add  t6, t6, s8
    sh   t5, 0(t6)
    # TY[k] = (n*C + gm*S) >> 1
    mv   a1, s3
    lw   a0, N(sp)
    call fp_mul
    sw   a0, SCR(sp)
    mv   a1, s2
    lw   a0, GM(sp)
    call fp_mul
    lw   t5, SCR(sp)
    add  t5, t5, a0
    srai t5, t5, 1
    sh   t5, 512(t6)
    # TZ[k] = (e*S) >> 1
    mv   a1, s2
    lw   a0, E(sp)
    call fp_mul
    srai a0, a0, 1
    sh   a0, 1024(t6)
    # TN[k] = -(W*S + n*C) >> 1
    mv   a1, s2
    lw   a0, W(sp)
    call fp_mul
    sw   a0, SCR(sp)
    mv   a1, s3
    lw   a0, N(sp)
    call fp_mul
    lw   t5, SCR(sp)
    add  t5, t5, a0
    sub  t5, zero, t5
    srai t5, t5, 1
    sh   t5, 1536(t6)
    # Second table bank (base s5): XS, YS, ZS, NS
    slli t6, s0, 1
    add  t6, t6, s5
    # XS[k] = en*S
    mv   a1, s2
    lw   a0, EN(sp)
    call fp_mul
    sh   a0, 0(t6)
    # YS[k] = -em*S
    mv   a1, s2
    lw   a0, EM(sp)
    call fp_mul
    sub  a0, zero, a0
    sh   a0, 512(t6)
    # ZS[k] = g*S
    mv   a1, s2
    lw   a0, G(sp)
    call fp_mul
    sh   a0, 1024(t6)
    # NS[k] = V*S
    mv   a1, s2
    lw   a0, V(sp)
    call fp_mul
    sh   a0, 1536(t6)
    addi s0, s0, 1
    sltiu t0, s0, 256
    bnez t0, tbl_loop

    # ── Render: ii = ring angle (outer, step 1), jj = tube (inner, 3) ─
    li   s0, 0                # s0 = ii
i_loop:
    la   t0, sintab
    slli t1, s0, 1
    add  t1, t1, t0
    lh   t2, 0(t1)            # c = sin(alpha)
    addi t1, s0, 64
    andi t1, t1, 0xff
    slli t1, t1, 1
    add  t1, t1, t0
    lh   t1, 0(t1)            # l = cos(alpha)
    sw   t1, L_ST(sp)
    sw   t2, C_ST(sp)
    # XI = 2*(l*m - c*gn)
    lw   a1, L_ST(sp)
    lw   a0, M(sp)
    call fp_mul
    sw   a0, SCR(sp)
    lw   a1, C_ST(sp)
    lw   a0, GN(sp)
    call fp_mul
    lw   t3, SCR(sp)
    sub  s2, t3, a0
    slli s2, s2, 1
    # YI = 2*(l*n + c*gm)
    lw   a1, L_ST(sp)
    lw   a0, N(sp)
    call fp_mul
    sw   a0, SCR(sp)
    lw   a1, C_ST(sp)
    lw   a0, GM(sp)
    call fp_mul
    lw   t3, SCR(sp)
    add  s3, t3, a0
    slli s3, s3, 1
    # ZI = 2*(e*c)
    lw   a1, C_ST(sp)
    lw   a0, E(sp)
    call fp_mul
    slli s4, a0, 1

    li   s1, 0                # s1 = jj
j_loop:
    slli t0, s1, 1
    add  t0, t0, s5          # t0 = &XS[jj]
    add  t1, s0, s1          # p = ii + jj (<= 510)
    andi t2, t1, -256        # t2 != 0 iff p >= 256
    beqz t2, 1f
    addi t1, t1, -256
1:  slli t1, t1, 1
    add  t1, t1, s8          # t1 = &TX[p]
    sub  t2, s0, s1          # q = ii - jj (>= -255)
    bgez t2, 2f
    addi t2, t2, 256
2:  slli t2, t2, 1
    add  t2, t2, s8          # t2 = &TX[q]
    # x'' = TX[p] + TX[q] + XI + XS[jj]
    lh   t3, 0(t1)
    lh   t4, 0(t2)
    add  t3, t3, t4
    add  t3, t3, s2
    lh   t4, 0(t0)
    add  t3, t3, t4
    # y'' = TY[p] + TY[q] + YI + YS[jj]
    lh   t4, 512(t1)
    lh   t5, 512(t2)
    add  t4, t4, t5
    add  t4, t4, s3
    lh   t5, 512(t0)
    add  t4, t4, t5
    # z' = TZ[p] + TZ[q] + ZI + ZS[jj]
    lh   t5, 1024(t1)
    lh   t6, 1024(t2)
    add  t5, t5, t6
    add  t5, t5, s4
    lh   t6, 1024(t0)
    add  t5, t5, t6
    # lum = TN[p] + TN[q] + NS[jj]
    lh   t6, 1536(t1)
    lh   a0, 1536(t2)
    add  t6, t6, a0
    lh   a0, 1536(t0)
    add  t6, t6, a0
    # sx = 40 + (8*x'') >> 12
    slli a0, t3, 3
    srai a0, a0, 12
    addi a0, a0, 40
    # sy = 13 + (4*y'') >> 12
    slli a1, t4, 2
    srai a1, a1, 12
    addi a1, a1, 13
    # bounds: 0 <= sx < 80, 0 <= sy < 26 (unsigned compare)
    sltiu a2, a0, 80
    sltiu t3, a1, 26
    and  a2, a2, t3
    beqz a2, j_next
    # o = 80*sy + sx
    slli t3, a1, 4
    slli t4, a1, 6
    add  t3, t3, t4
    add  t3, t3, a0          # t3 = o
    slli t4, t3, 1
    add  t4, t4, s6          # &zbuf[o]
    lh   a2, 0(t4)
    blt  t5, a2, 3f          # closer (smaller z') -> plot
    j    j_next
3:  sh   t5, 0(t4)           # zbuf[o] = z'
    # char index = clamp(lum >> 9, 0, 11)
    srai a2, t6, 9
    bgez a2, 4f
    li   a2, 0
4:  li   t1, 11
    bge  t1, a2, 5f
    li   a2, 11
5:  la   t1, ramp
    add  t1, t1, a2
    lbu  a0, 0(t1)
    add  t1, s7, t3          # &chars[o]
    sb   a0, 0(t1)
j_next:
    addi s1, s1, 3
    sltiu t0, s1, 256
    bnez t0, j_loop
    addi s0, s0, 1
    sltiu t0, s0, 256
    bnez t0, i_loop

    # ── Print frame: ESC[H, then ROWS x (CRLF + 80 chars) ────────────
    li   a0, 27
    jal  putc
    li   a0, '['
    jal  putc
    li   a0, 'H'
    jal  putc
    li   s1, CHARS
    li   s2, ROWS
    li   s3, COLS
p_row:
    li   a0, '\n'
    jal  putc
    li   a0, '\r'
    jal  putc
p_col:
    lbu  a0, 0(s1)
    jal  putc
    addi s1, s1, 1
    addi s3, s3, -1
    bnez s3, p_col
    li   s3, COLS
    addi s2, s2, -1
    bnez s2, p_row

    # ── Spin: A += 2, B += 1 (mod 256) ───────────────────────────────
    addi s9, s9, 2
    andi s9, s9, 0xff
    addi s10, s10, 1
    andi s10, s10, 0xff
    j    frame

# ── putc: write the byte in a0 to the UART THR ──────────────────────
# Polls LSR.TEMT first.  Clobbers t0-t2; preserves a1 and s-regs.
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

# ── mul16: signed 16x16 -> 32-bit product ───────────────────────────
# a0 * a1 -> a0.  |a0| must be < 32768 (all our Q4.12 operands are
# <= 8192); a1 is full signed 32-bit.  16 shift-add iterations, with
# bit 15 of the multiplier weighted negatively (two's complement).
# Clobbers t0-t3, a0; preserves a1.
mul16:
    li   t0, 15
    slli t1, a0, 16
    srli t1, t1, 16          # a0's low 16 bits, unsigned
    mv   t2, a1              # multiplicand, shifted left each step
    li   a0, 0
1:  andi t3, t1, 1
    beqz t3, 2f
    add  a0, a0, t2
2:  srli t1, t1, 1
    slli t2, t2, 1
    addi t0, t0, -1
    bnez t0, 1b
    andi t3, t1, 1           # bit 15: negative weight
    beqz t3, 3f
    sub  a0, a0, t2
3:  ret

# ── fp_mul: Q4.12 fixed-point multiply ──────────────────────────────
# a0 * a1 -> a0 = (a0 * a1) >> 12 (arithmetic shift).  Clobbers ra, a0.
fp_mul:
    addi sp, sp, -4
    sw   ra, 0(sp)
    call mul16
    srai a0, a0, 12
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

.section .rodata
banner:
    .ascii "DONUT RV32I\n\r"
    .byte 0
ramp:
    .ascii ".,-~:;=!*#$@"
    .byte 0

.align 2
sintab:
    .half 0, 101, 201, 301, 401, 501, 601, 700
    .half 799, 897, 995, 1092, 1189, 1285, 1380, 1474
    .half 1567, 1660, 1751, 1842, 1931, 2019, 2106, 2191
    .half 2276, 2359, 2440, 2520, 2598, 2675, 2751, 2824
    .half 2896, 2967, 3035, 3102, 3166, 3229, 3290, 3349
    .half 3406, 3461, 3513, 3564, 3612, 3659, 3703, 3745
    .half 3784, 3822, 3857, 3889, 3920, 3948, 3973, 3996
    .half 4017, 4036, 4052, 4065, 4076, 4085, 4091, 4095
    .half 4096, 4095, 4091, 4085, 4076, 4065, 4052, 4036
    .half 4017, 3996, 3973, 3948, 3920, 3889, 3857, 3822
    .half 3784, 3745, 3703, 3659, 3612, 3564, 3513, 3461
    .half 3406, 3349, 3290, 3229, 3166, 3102, 3035, 2967
    .half 2896, 2824, 2751, 2675, 2598, 2520, 2440, 2359
    .half 2276, 2191, 2106, 2019, 1931, 1842, 1751, 1660
    .half 1567, 1474, 1380, 1285, 1189, 1092, 995, 897
    .half 799, 700, 601, 501, 401, 301, 201, 101
    .half 0, -101, -201, -301, -401, -501, -601, -700
    .half -799, -897, -995, -1092, -1189, -1285, -1380, -1474
    .half -1567, -1660, -1751, -1842, -1931, -2019, -2106, -2191
    .half -2276, -2359, -2440, -2520, -2598, -2675, -2751, -2824
    .half -2896, -2967, -3035, -3102, -3166, -3229, -3290, -3349
    .half -3406, -3461, -3513, -3564, -3612, -3659, -3703, -3745
    .half -3784, -3822, -3857, -3889, -3920, -3948, -3973, -3996
    .half -4017, -4036, -4052, -4065, -4076, -4085, -4091, -4095
    .half -4096, -4095, -4091, -4085, -4076, -4065, -4052, -4036
    .half -4017, -3996, -3973, -3948, -3920, -3889, -3857, -3822
    .half -3784, -3745, -3703, -3659, -3612, -3564, -3513, -3461
    .half -3406, -3349, -3290, -3229, -3166, -3102, -3035, -2967
    .half -2896, -2824, -2751, -2675, -2598, -2520, -2440, -2359
    .half -2276, -2191, -2106, -2019, -1931, -1842, -1751, -1660
    .half -1567, -1474, -1380, -1285, -1189, -1092, -995, -897
    .half -799, -700, -601, -501, -401, -301, -201, -101
