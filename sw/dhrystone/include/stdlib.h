/* Freestanding stdlib.h shim for Dhrystone on virdant-riscv.
 * malloc is a bump allocator off the end of .bss; free is a no-op. */
#ifndef DHRY_STDLIB_H
#define DHRY_STDLIB_H

void *malloc (unsigned n);
void  free   (void *p);

#endif /* DHRY_STDLIB_H */
