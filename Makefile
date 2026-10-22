VIR ?= vir
VIRT ?= ../virdant-virt/target/debug/virt

TRACE ?= 0
TRACE_FLAGS = $(if $(filter 1,$(TRACE)),--vcd=build/$@.vcd,)
SCOREBOARD_TRACE = $(if $(filter 1,$(TRACE)),--trace,)

ASM=loop.s
HEX=build/$(ASM:.s=.hex)
VERILATOR_ROOT=$(shell verilator -V | grep VERILATOR_ROOT | awk '{print $$3}' | head -n1)
VIR_SOURCES := $(wildcard src/*.vir)
SV_SOURCES := $(wildcard ext/*.sv)

# Run the RISC-V ISA tests on the virt simulator.  Each test is converted
# to a flash image (bootloader + ELF) and run; the test's exit code comes
# from the platform's `exit` port (a0 at the tests' ecall).
scoreboard: build/Top build/boot.bin
	./scoreboard.py $(SCOREBOARD_TRACE)

# ── UART echo demo ───────────────────────────────────────────────────

sw/uart_demo/echo.elf: sw/uart_demo/echo.s sw/uart_demo/link.ld
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -static \
		-T sw/uart_demo/link.ld -o $@ sw/uart_demo/echo.s

# Flash image: bootloader + echo program (copied to RAM 0x80000000).
echo.flash: sw/uart_demo/echo.elf build/boot.bin
	./elf2flash.py $< --boot build/boot.bin -o echo.flash

# Build and run the UART echo server interactively (Ctrl+C to stop).
# Type characters; the RISC-V core echoes them back over the UART.
echo: build/Top echo.flash
	./build/Top --flash=echo.flash $(TRACE_FLAGS)

# ── Mandelbrot demo ──────────────────────────────────────────────────

sw/mandelbrot/mandelbrot.elf:
	$(MAKE) -C sw/mandelbrot mandelbrot.elf

# Flash image: bootloader + Mandelbrot renderer (copied to RAM 0x80000000).
mandelbrot.flash: sw/mandelbrot/mandelbrot.elf build/boot.bin
	./elf2flash.py $< --boot build/boot.bin -o mandelbrot.flash

# Build and run the ASCII Mandelbrot renderer (80x24 over UART; exits
# with code 0 when the rendering completes).
mandelbrot: build/Top mandelbrot.flash
	./build/Top --flash=mandelbrot.flash $(TRACE_FLAGS)

.PHONY: mandelbrot

# ── Spinning donut demo ─────────────────────────────────────────────

sw/donut/donut.elf:
	$(MAKE) -C sw/donut donut.elf

# Flash image: bootloader + spinning ASCII donut (copied to RAM 0x80000000).
donut.flash: sw/donut/donut.elf build/boot.bin
	./elf2flash.py $< --boot build/boot.bin -o donut.flash

# Build and run the spinning donut (animates forever over UART; Ctrl+C
# to stop).
donut: build/Top donut.flash
	./build/Top --flash=donut.flash $(TRACE_FLAGS)

.PHONY: donut

# ── Dhrystone benchmark ──────────────────────────────────────────────

sw/dhrystone/dhrystone.elf:
	$(MAKE) -C sw/dhrystone dhrystone.elf

# Flash image: bootloader + Dhrystone (copied to RAM 0x80000000).
dhrystone.flash: sw/dhrystone/dhrystone.elf build/boot.bin
	./elf2flash.py $< --boot build/boot.bin -o dhrystone.flash

# Build and run Dhrystone (prints results, then exits).
dhrystone: build/Top dhrystone.flash
	./build/Top --flash=dhrystone.flash $(TRACE_FLAGS)

.PHONY: dhrystone

build/sim: sim.cpp $(VIR_SOURCES) $(SV_SOURCES) build/
	verilator \
		--sv \
		--cc build/*.sv \
		--Mdir build \
		--prefix Vvirt \
		--top-module Top \
		--build \
		-Wno-UNOPTFLAT \
		--trace-vcd
	g++ \
		-Ibuild/ \
		-I$(VERILATOR_ROOT)/include \
		-I$(VERILATOR_ROOT)/include/vltstd \
		$(VERILATOR_ROOT)/include/verilated_vcd_c.cpp \
		sim.cpp \
		build/verilated.o \
		build/verilated_threads.o \
		build/VTop__ALL.o \
		-O2 \
		-lelf \
		-o build/sim

build: build/

build/: $(VIR_SOURCES)
	$(VIR) build
	cp ext/* build/

build/%.hex: %.s
	./asm2hex.sh $< $@

run: build/sim $(HEX)
	echo $(HEX)
	./build/sim $(HEX)

out.vcd: run

wave: out.vcd $(HEX)
	gtkwave sim.gtkw

wave-spi: build/dump.vcd
	gtkwave build/dump.vcd spi.gtkw

wave-uart: build/uart_dump.vcd
	gtkwave build/uart_dump.vcd

build_tests:
	mkdir -p build
	bash get_riscv_tests.sh

test_spi: tb/spi_tb.sv build
	iverilog -g2012 -o build/spi_tb.vvp build/spi.sv tb/spi_tb.sv
	cd build && vvp spi_tb.vvp

test_uart: tb/uart_tb.sv build
	iverilog -g2012 -o build/uart_tb.vvp build/uart.sv tb/uart_tb.sv
	cd build && vvp uart_tb.vvp

test_wbuart: tb/wbuart_tb.sv build
	iverilog -g2012 -o build/wbuart_tb.vvp build/uart.sv tb/wbuart_tb.sv
	cd build && vvp wbuart_tb.vvp

# ── virt (Verilator) flow ──────────────────────────────────────────────

# The simulator binary for the virt::Virt platform, built by `virt build`
# (which runs `vir build`, copies ext/*.sv, then Verilator + link).
build/Top: $(VIR_SOURCES) $(SV_SOURCES)
	$(VIRT) build

# The XIP flash bootloader: copies the test image from flash (offset
# 0x1000) to RAM at 0x80000000 and jumps to it.  See boot/boot.s.
build/boot.bin: boot/boot.s boot/link.ld
	mkdir -p build
	riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib -static \
		-T boot/link.ld -o build/boot.elf boot/boot.s
	riscv64-unknown-elf-objcopy -O binary build/boot.elf build/boot.bin

synth: $(VIR_SOURCES) $(SV_SOURCES)
	$(VIR) build
	cp ext/* build/
	yosys -p "synth_ice40 -top Top -json build/top.json" build/*.sv 2>&1 | tee build/yosys.log
	nextpnr-ice40 --up5k --package sg48 \
		--json build/top.json \
		--pcf icesugar.pcf \
		--pcf-allow-unconstrained \
		--asc build/top.asc 2>&1 | tee build/nextpnr-ice40.log

clean:
	rm -rf build/
	rm -f out.vcd echo.flash
	make -C riscv-tests clean || exit 0
