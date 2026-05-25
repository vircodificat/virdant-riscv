# ─────────────────────────────────────────────────────────────────────
# Makefile — UART Echo Server (sw/uart_demo)
#
# Builds the echo-server ELF for the Virdant RISC-V SoC and runs it
# under the Verilator simulation with --uart enabled.
#
# Usage:
#   make              — build uart_demo.elf
#   make run          — build + run under the simulator with --uart
#   make clean        — remove build artefacts
# ─────────────────────────────────────────────────────────────────────

TARGET   := uart_demo.elf
SRC      := main.c
LINK_SCRIPT := link.ld

# RISC-V toolchain (64-bit host GCC targeting rv32i).
RISCV_GCC   := riscv64-unknown-elf-gcc
RISCV_OBJDUMP := riscv64-unknown-elf-objdump

# Path to the Verilator simulator (relative to this directory).
SIM := ../../build/sim

# Compiler flags: RV32I, bare-metal, no standard libs.
CFLAGS := \
    -march=rv32i       \
    -mabi=ilp32        \
    -nostdlib          \
    -nostartfiles      \
    -nodefaultlibs     \
    -static            \
    -mcmodel=medany    \
    -Os                \
    -ffreestanding     \
    -fno-builtin       \
    -Wall -Wextra

LDFLAGS := \
    -T $(LINK_SCRIPT)  \
    -Wl,-Map=$(TARGET:.elf=.map)

# ─── Targets ────────────────────────────────────────────────────────

.PHONY: all run clean dump

all: $(TARGET)

$(TARGET): $(SRC) $(LINK_SCRIPT)
	$(RISCV_GCC) $(CFLAGS) $(LDFLAGS) $(SRC) -o $@
	$(RISCV_GCC) $(CFLAGS) -c $(SRC) -o $(SRC:.c=.o)
	@echo "  >> Built $@ ($$($(RISCV_OBJDUMP) -t $@ | grep -c ' F ') functions)"

run: $(TARGET)
	@echo "  >> Starting UART echo server simulation..."
	@echo "  >> Type characters — the RISC-V core will echo them back."
	@echo ""
	$(SIM) --uart $(TARGET)

dump: $(TARGET)
	$(RISCV_OBJDUMP) --disassemble-all --disassemble-zeroes $(TARGET) | less

clean:
	rm -f $(TARGET) $(TARGET:.elf=.map) $(SRC:.c=.o)
