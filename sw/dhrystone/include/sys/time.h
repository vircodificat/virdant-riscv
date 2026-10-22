/* Freestanding sys/time.h shim for Dhrystone on virdant-riscv.
 * Kept for the source's struct timeval declaration; actual timing is
 * done with the cycle counter (see rdcycle in dhry_1.c). */
#ifndef DHRY_SYS_TIME_H
#define DHRY_SYS_TIME_H

struct timeval {
    long tv_sec;
    long tv_usec;
};

#endif /* DHRY_SYS_TIME_H */
