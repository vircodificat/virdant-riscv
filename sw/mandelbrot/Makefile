# sw/mandelbrot — ASCII Mandelbrot renderer for virdant-riscv.
#
# Builds mandelbrot.elf (RV32I, no stdlib); the top-level Makefile turns
# it into a flash image with elf2flash.py and runs it on the simulator.

CROSS   ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc

all: mandelbrot.elf

mandelbrot.elf: main.s link.ld
	$(CC) -march=rv32i -mabi=ilp32 -nostdlib -static \
		-T link.ld -o $@ main.s

clean:
	rm -f mandelbrot.elf

.PHONY: all clean
