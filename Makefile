VERILATOR_ROOT=$(shell verilator -V | grep VERILATOR_ROOT | awk '{print $$3}' | head -n1)
build/sim: sim.cpp
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

out.vcd: build/sim
	./build/sim

wave: out.vcd rom.hex
	gtkwave sim.gtkw

clean:
	rm -rf build/
