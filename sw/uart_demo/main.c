// ─────────────────────────────────────────────────────────────────────
// UART Echo Server — Virdant RISC-V SoC
//
// Polls the Wishbone-attached UART (WbUart) at 0x40000000 and echoes
// every received character back to the transmitter.
//
// Register map (src/uart.vir — WbUart):
//   Offset 0x00  RBR/THR  (read = receiver byte, write = transmit byte)
//   Offset 0x04  LSR      (Line Status Register, read only)
//     bit 0 : DR   — Data Ready (rx_pending)
//     bit 5 : TEMT — Transmitter Empty (sender.ready)
//     bit 6 : THRE — Transmitter Holding Register Empty (sender.ready)
//
// Build:  riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib ...
// Run:    ./build/sim --uart sw/uart_demo/uart_demo.elf
// ─────────────────────────────────────────────────────────────────────

// UART base address (nybble 0x4 → 0x4000_0000 in WbAddrMuxNybble).
#define UART_BASE  ((volatile unsigned int *)0x40000000UL)

// Word offsets (32-bit word = 4 bytes, so offset 0x04 → index 1).
#define REG_THR  0   // Transmit Holding Register  (write-only)
#define REG_RBR  0   // Receiver Buffer Register   (read-only)
#define REG_LSR  1   // Line Status Register       (read-only)

// LSR bit flags.
#define LSR_DR   (1u << 0)  // Data Ready
#define LSR_TEMT (1u << 5)  // Transmitter Empty

// Linker-provided stack top.
extern unsigned int __stack_top;

void puts(unsigned char *dat) {
    unsigned char b = *dat;
    while (b) {
        dat++;
        *UART_BASE = b;
        b = *dat;
    }
}

// ─────────────────────────────────────────────────────────────────────
// _start — entry point, called directly by the CPU reset vector.
//
// Sets up the stack pointer, clears BSS, then enters the echo loop.
// ─────────────────────────────────────────────────────────────────────
void _start(void) {
    // Set the stack pointer before any C code runs.
    register unsigned int *sp asm("sp") = &__stack_top;
    (void)sp;

    // Clear BSS (uninitialised data).
    extern unsigned int __bss_start, __bss_end;
    for (unsigned int *b = &__bss_start; b < &__bss_end; *b++ = 0) ;

    while (1) {
        puts("Hello\n");
    }

    // ── Echo loop ──────────────────────────────────────────────────
    while (1) {
        // 1. Wait until a character arrives (Data Ready flag).
        while (!(UART_BASE[REG_LSR] & LSR_DR)) ;

        // 2. Read the received byte from RBR.
        unsigned char c = (unsigned char)(UART_BASE[REG_RBR] & 0xff);

        // 3. Wait until the transmitter is ready to accept a new byte.
        while (!(UART_BASE[REG_LSR] & LSR_TEMT)) ;

        // 4. Write the byte back to THR — the hardware serialises it.
        UART_BASE[REG_THR] = c;
    }
}
