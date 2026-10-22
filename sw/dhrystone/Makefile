# sw/dhrystone — Dhrystone 2.1 for virdant-riscv.
#
# Builds dhrystone.elf for the RV32I core (no M extension: multiply and
# divide come from libgcc; no libc: freestanding shims live in libc.c,
# with stub headers under include/).  The top-level Makefile turns the
# ELF into a flash image with elf2flash.py and runs it on the simulator.
#
# NRUNS is compile-time (the interactive prompt is skipped); the timing
# is the machine cycle counter (CSR 0xC00), reported as DMIPS at the
# 48 MHz virt platform clock.

CROSS   ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc

MARCH   := rv32i_zicsr
CFLAGS  := -march=$(MARCH) -mabi=ilp32 -O2 -ffreestanding \
           -Iinclude -DNRUNS=10000

all: dhrystone.elf

dhrystone.elf: crt0.S dhry_1.c dhry_2.c dhry.h libc.c include/stdio.h \
               include/string.h include/stdlib.h include/sys/time.h link.ld
	$(CC) $(CFLAGS) -nostdlib -static -T link.ld -o $@ \
		crt0.S dhry_1.c dhry_2.c libc.c -lgcc

clean:
	rm -f dhrystone.elf

.PHONY: all clean
