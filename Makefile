ASM=loop.s
HEX=build/$(ASM:.s=.hex)
VERILATOR_ROOT=$(shell verilator -V | grep VERILATOR_ROOT | awk '{print $$3}' | head -n1)
VIR_SOURCES := $(wildcard src/*.vir)
SV_SOURCES := $(wildcard ext/*.sv)

build/sim: sim.cpp $(VIR_SOURCES) $(SV_SOURCES)
	vir build
	cp ext/* build/
	verilator \
		--cc build/*.sv \
		--Mdir build \
		--top-module Top \
		--build \
		--trace-vcd
	g++ \
		-Ibuild/ \
		-I$(VERILATOR_ROOT)/include \
		$(VERILATOR_ROOT)/include/verilated_vcd_c.cpp \
		sim.cpp \
		build/verilated.o \
		build/verilated_threads.o \
		build/VTop__ALL.o \
		-O2 \
		-o build/sim

build/%.hex: %.s
	./asm2hex.sh $< $@

run: build/sim $(HEX)
	./build/sim $(HEX)

out.vcd: run

wave: out.vcd $(HEX)
	gtkwave sim.gtkw

build_tests:
	mkdir -p build
	bash get_riscv_tests.sh

clean:
	rm -rf build/
	rm -f out.vcd
	rm -rf riscv-tests/
