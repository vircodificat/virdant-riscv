.section .text
.globl _start

# UART base address (nybble 0x4 -> 0x40000000)
.equ UART_BASE, 0x40000000
.equ UART_LSR,  0x40000004

# LSR bit flags
.equ LSR_DR,   1      # bit 0: Data Ready
.equ LSR_TEMT, (1<<5) # bit 5: Transmitter Empty

_start:
    # Set up a stack pointer (needed for nothing here, but good practice)
    lui sp, 0x80001     # sp = 0x80001000 (top of 4KB stack above code)

    # Load UART base into t0
    lui t0, 0x40000     # t0 = 0x40000000 (UART base)
    addi t1, t0, 4      # t1 = 0x40000004 (LSR address)

loop:
    # Wait for a character (poll LSR.DR)
1:  lw t2, 0(t1)        # Read LSR
    andi t2, t2, 1      # Check bit 0 (DR)
    beqz t2, 1b         # Not ready, keep polling

    # Read the character from RBR
    lw t3, 0(t0)        # Read RBR (low byte has the data)

    # Wait for transmitter to be ready (poll LSR.TEMT)
2:  lw t2, 0(t1)        # Read LSR
    andi t2, t2, 32     # Check bit 5 (TEMT)
    beqz t2, 2b         # Not ready, keep polling

    # Echo the character back
    sw t3, 0(t0)        # Write THR

    # Repeat
    j loop