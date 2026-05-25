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

// Forward declarations.
unsigned char getc();
void putc(unsigned char c);
void puts(unsigned char *dat);

// ─────────────────────────────────────────────────────────────────────
// _start — entry point, called directly by the CPU reset vector.
//
// Placed first so it lands at 0x80000000, matching the CPU reset vector.
// Sets up the stack pointer, clears BSS, then echoes received characters.
// ─────────────────────────────────────────────────────────────────────
__attribute__((section(".text.start"))) void _start(void) {
    // Set the stack pointer before any C code runs.
    __asm__ volatile("la sp, __stack_top" : : : "sp");

    // Clear BSS (uninitialised data).
    extern unsigned int __bss_start, __bss_end;
    for (unsigned int *b = &__bss_start; b < &__bss_end; *b++ = 0) ;

    // ── Echo loop ──────────────────────────────────────────────────
    while (1) {
        unsigned char c = getc();
        putc(c);
    }
}

unsigned char getc(void) {
    // 1. Wait until a character arrives (Data Ready flag).
    while (!(UART_BASE[REG_LSR] & LSR_DR)) ;

    // 2. Read the received byte from RBR.
    return (unsigned char)(UART_BASE[REG_RBR] & 0xff);
}

/// Write a single character to the UART, busy-waiting for the transmitter
/// to be ready (TEMT = Transmitter Empty).
void putc(unsigned char c) {
    while (!(UART_BASE[REG_LSR] & LSR_TEMT)) ;
    UART_BASE[REG_THR] = c;
}

void puts(unsigned char *dat) {
    while (*dat) {
        putc(*dat);
        dat++;
    }
}
