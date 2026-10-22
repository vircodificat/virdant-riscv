# boot/boot.s — virt flash bootloader for the RISC-V ISA tests.
#
# The CPU resets to 0x20000000 and executes in place from the emulated SPI
# flash (XIP).  This bootloader occupies flash offsets [0, 0x1000); the test
# image is embedded at flash offset 0x1000 by elf2flash.py (--boot), mapped
# so that image byte S lands at flash 0x1000+S and is copied to
# RAM 0x80000000+S.  The relative offsets between ELF segments are
# preserved, so e.g. .tohost (linked at 0x80001000) is image offset 0x1000,
# flash 0x2000, and lands in RAM at 0x80001000 as linked.
#
# The tests are linked at 0x80000000 with absolute references (stack pointers,
# trap vectors), so they must run from RAM: this stage copies the image into
# RAM and jumps to it.
#
# Fully position-independent (absolute constants, PC-relative branches),
# so it can execute from flash via the slow SPI fetch path.

.section .text.init
.globl _start

.equ SPI_BASE,   0x20000000       # flash MMIO window (reads: 0x03 READ)
.equ IMAGE_OFF,  0x1000           # image base within the flash
.equ RAM_BASE,   0x80000000       # destination (tests are linked here)
.equ COPY_LEN,   0x8000           # bytes to copy (Dhrystone image needs
                                  # more than the original 8 KiB)
.equ UART_BASE, 0x40000000       # WbUart MMIO base (RBR/THR at +0x00)
.equ UART_LSR,  0x40000004       # WbUart Line Status Register (+0x04)
.equ LSR_TEMT,  (1 << 5)         # LSR bit 5: Transmitter Empty

_start:
    la   a0, booting_str
    jal  print

    # t0 = flash read cursor, t1 = RAM write cursor, t2 = bytes left.
    li   t0, SPI_BASE + IMAGE_OFF
    li   t1, RAM_BASE
    li   t2, COPY_LEN

1:  # Copy one word.  The lw goes to the SPI region and stalls the
    # pipeline until the flash read acks; the sw lands in RAM.
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -4
    bnez t2, 1b

    # Print "READY\n\r" over UART before jumping to the test image.
    la   a0, ready_str
    jal  print

    # Jump into the copied image (absolute: tests are linked at RAM_BASE).
    li   t0, RAM_BASE
    jr   t0

# ── Print "READY\n\r" via UART ──────────────────────────────────────
# Uses only temporary registers; no stack needed.
print:
    li   t3, UART_BASE
    li   t4, UART_LSR
1:  # Wait for transmitter to be ready (poll LSR.TEMT).
    lw   t6, 0(t4)
    andi t6, t6, LSR_TEMT
    beqz t6, 1b
    # Load and write next character.
    lbu  t6, 0(a0)
    beqz t6, 2f              # null terminator → done
    sw   t6, 0(t3)
    addi a0, a0, 1
    j    1b
2:  ret

booting_str:
    .ascii "BOOTING...\n\r"
    .byte 0

ready_str:
    .ascii "READY\n\r"
    .byte 0
