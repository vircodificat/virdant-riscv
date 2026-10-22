/* Freestanding string.h shim for Dhrystone on virdant-riscv. */
#ifndef DHRY_STRING_H
#define DHRY_STRING_H

char       *strcpy  (char *dst, const char *src);
int         strcmp  (const char *a, const char *b);
unsigned    strlen  (const char *s);
void       *memset  (void *p, int c, unsigned n);
void       *memcpy  (void *dst, const void *src, unsigned n);

#endif /* DHRY_STRING_H */
