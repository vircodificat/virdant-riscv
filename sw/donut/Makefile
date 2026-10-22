# sw/donut — spinning ASCII donut for virdant-riscv.
#
# Builds donut.elf (RV32I, no stdlib); the top-level Makefile turns
# it into a flash image with elf2flash.py and runs it on the simulator.

CROSS   ?= riscv64-unknown-elf-
CC      := $(CROSS)gcc

all: donut.elf

donut.elf: main.s link.ld
	$(CC) -march=rv32i -mabi=ilp32 -nostdlib -static \
		-T link.ld -o $@ main.s

clean:
	rm -f donut.elf

.PHONY: all clean
