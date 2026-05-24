ASM=loop.s
HEX=build/$(ASM:.s=.hex)
VERILATOR_ROOT=$(shell verilator -V | grep VERILATOR_ROOT | awk '{print $$3}' | head -n1)
VIR_SOURCES := $(wildcard src/*.vir)
SV_SOURCES := $(wildcard ext/*.sv)

build/sim: sim.cpp $(VIR_SOURCES) $(SV_SOURCES) build/
	verilator \
		--sv \
		--cc build/*.sv \
		--Mdir build \
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

build: $(VIR_SOURCES)
	vir build
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

test_spi: spi_tb.sv build
	iverilog -g2012 -o build/spi_tb.vvp build/spi.sv spi_tb.sv
	cd build && vvp spi_tb.vvp

test_uart: uart_tb.sv build
	iverilog -g2012 -o build/uart_tb.vvp build/uart.sv uart_tb.sv
	cd build && vvp uart_tb.vvp

scoreboard: build/sim
	./scoreboard.py

synth: $(VIR_SOURCES) $(SV_SOURCES)
	vir build
	cp ext/* build/
	yosys -p "synth_ice40 -top Top -json build/top.json" build/*.sv 2>&1 | tee build/yosys.log
	nextpnr-ice40 --up5k --package sg48 \
		--json build/top.json \
		--pcf icesugar.pcf \
		--pcf-allow-unconstrained \
		--asc build/top.asc 2>&1 | tee build/nextpnr-ice40.log

clean:
	rm -rf build/
	rm -f out.vcd
	make -C riscv-tests || exit 0
