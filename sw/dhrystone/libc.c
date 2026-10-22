/* libc.c — freestanding support for Dhrystone on virdant-riscv.
 *
 * UART I/O (RBR/THR at 0x40000000, LSR at 0x40000004, TEMT = bit 5),
 * a tiny integer-only printf, string/memory routines, a bump-allocation
 * malloc, and a scanf stub (the interactive prompt is never reached:
 * NRUNS is set at compile time).  No floating point is used anywhere,
 * so no soft-float libgcc routines are needed.
 */

#include <stdarg.h>

#define UART_BASE 0x40000000u
#define UART_LSR  0x40000004u
#define LSR_TEMT  (1u << 5)

int putchar (int c)
{
  volatile unsigned *thr = (volatile unsigned *) UART_BASE;
  volatile unsigned *lsr = (volatile unsigned *) UART_LSR;

  while ((*lsr & LSR_TEMT) == 0)
    ;
  *thr = (unsigned) c & 0xffu;
  return (unsigned char) c;
}

static void print_str (const char *s)
{
  while (*s)
    putchar (*s++);
}

static void print_dec_pad (unsigned long v, int width, char pad)
{
  char buf[12];
  int  i = 0;

  do
    {
      buf[i++] = '0' + (char) (v % 10);
      v /= 10;
    }
  while (v != 0);

  while (i < width)
    buf[i++] = pad;
  while (i > 0)
    putchar (buf[--i]);
}

static void print_dec (unsigned long v)
{
  print_dec_pad (v, 0, ' ');
}

static void print_hex (unsigned long v)
{
  int i;

  print_str ("0x");
  for (i = 28; i >= 0; i -= 4)
    {
      unsigned d = (v >> i) & 0xfu;
      putchar (d < 10 ? '0' + (int) d : 'a' + (int) d - 10);
    }
}

int printf (const char *fmt, ...)
{
  va_list ap;

  va_start (ap, fmt);
  while (*fmt != '\0')
    {
      if (*fmt != '%')
        {
          putchar (*fmt++);
          continue;
        }
      fmt++;
      /* Optional zero-pad flag and field width (e.g. %02d). */
      {
        char pad = ' ';
        int  width = 0;
        while (*fmt == '0' || (*fmt >= '1' && *fmt <= '9'))
          {
            if (*fmt == '0' && width == 0)
              pad = '0';
            else
              width = width * 10 + (*fmt - '0');
            fmt++;
          }
        switch (*fmt)
          {
          case 'd':
            {
              long v = va_arg (ap, int);
              if (v < 0)
                {
                  putchar ('-');
                  if (width > 0)
                    width--;
                  print_dec_pad ((unsigned long) -(unsigned long) v,
                                 width, pad);
                }
              else
                print_dec_pad ((unsigned long) v, width, pad);
            }
            break;
          case 'u':
            print_dec_pad (va_arg (ap, unsigned), width, pad);
            break;
          case 'x':
            print_hex (va_arg (ap, unsigned));
            break;
          case 'p':
            print_hex ((unsigned long) va_arg (ap, void *));
            break;
          case 'c':
            putchar (va_arg (ap, int));
            break;
          case 's':
            print_str (va_arg (ap, const char *));
            break;
          case '%':
            putchar ('%');
            break;
          case '\0':
            fmt--;
            break;
          default:
            putchar ('%');
            putchar (*fmt);
            break;
          }
      }
      fmt++;
    }
  va_end (ap);
  return 0;
}

char *strcpy (char *dst, const char *src)
{
  char *d = dst;

  while ((*d++ = *src++) != '\0')
    ;
  return dst;
}

int strcmp (const char *a, const char *b)
{
  while (*a != '\0' && *a == *b)
    {
      a++;
      b++;
    }
  return (int) (unsigned char) *a - (int) (unsigned char) *b;
}

unsigned strlen (const char *s)
{
  const char *p = s;

  while (*p != '\0')
    p++;
  return (unsigned) (p - s);
}

void *memset (void *p, int c, unsigned n)
{
  unsigned char *q = p;

  while (n-- > 0)
    *q++ = (unsigned char) c;
  return p;
}

void *memcpy (void *dst, const void *src, unsigned n)
{
  unsigned char *d = dst;
  const unsigned char *s = src;

  while (n-- > 0)
    *d++ = *s++;
  return dst;
}

/* Heap: bump allocator starting at the end of .bss.  The benchmark
 * allocates two records and frees them immediately; the stack grows
 * down from __stack_top, well above anything malloc returns here. */
extern char __bss_end[];

static char *heap_ptr = __bss_end;

void *malloc (unsigned n)
{
  void *p = heap_ptr;

  n = (n + 3u) & ~3u;
  heap_ptr += n;
  return p;
}

void free (void *p)
{
  (void) p;                    /* bump allocator: no-op */
}

int scanf (const char *fmt, ...)
{
  (void) fmt;
  return -1;                   /* stub: unreachable with NRUNS > 0 */
}
