/* Freestanding stdio shim for Dhrystone on virdant-riscv.
 * printf supports %c %s %d %u %x %p %% (integer formats only; the
 * benchmark's float reporting is converted to integer math). */
#ifndef DHRY_STDIO_H
#define DHRY_STDIO_H

int printf  (const char *fmt, ...);
int putchar (int c);
int scanf   (const char *fmt, ...);   /* stub: never reached (NRUNS > 0) */

#endif /* DHRY_STDIO_H */
